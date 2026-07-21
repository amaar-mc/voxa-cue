import Foundation
import VoxaCore

public enum VoxaAPIError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidPayload
    case cancelled
    case timedOut(requestID: String?)
    case offline
    case transport
    case unauthorized(requestID: String?)
    case rateLimited(retryAfterSeconds: Int?, requestID: String?)
    case unavailable(requestID: String?)
    case contractMismatch(requestID: String?)
    case rejected(statusCode: Int, code: String, message: String, requestID: String?)
}

public struct VoxaAPIHealth: Decodable, Equatable, Sendable {
    public let status: String
    public let service: String
    public let schemaVersion: Int
    public let build: String
}

public actor VoxaAPIClient {
    private static let maximumResponseBytes = 2 * 1_024 * 1_024

    private let baseURL: URL
    private let bearerToken: String
    private let session: URLSession
    private let requestTimeoutSeconds: TimeInterval
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        bearerToken: String,
        session: URLSession,
        requestTimeoutSeconds: TimeInterval
    ) {
        precondition(requestTimeoutSeconds > 0)
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func readiness() async throws -> VoxaAPIHealth {
        try await get(path: "/readyz", response: VoxaAPIHealth.self)
    }

    public func createDeckPlan(
        title: String,
        targetDurationSeconds: Int,
        slides: [DeckSlide]
    ) async throws -> DeckPlan {
        let payload = DeckPlanRequest(
            schemaVersion: 1,
            locale: "en-US",
            title: title,
            targetDurationSeconds: targetDurationSeconds,
            slides: slides.map {
                DeckSlideRequest(
                    slideIndex: $0.index,
                    title: $0.title,
                    visibleText: $0.body,
                    speakerNotes: $0.notes
                )
            }
        )
        let plan: DeckPlan = try await post(path: "/v1/deck-plans", payload: payload, response: DeckPlan.self)
        guard deckPlanIsValid(
            plan,
            expectedTitle: title,
            targetDurationSeconds: targetDurationSeconds,
            validSlideIndexes: Set(slides.map(\.index))
        ) else {
            throw VoxaAPIError.contractMismatch(requestID: nil)
        }
        return plan
    }

    public func createInsight(
        summary: SessionSummary,
        checkpoints: [SessionCheckpointResult],
        cueEvents: [SessionCueEvent]
    ) async throws -> CoachingInsight {
        let payload = InsightRequest(
            schemaVersion: 1,
            sessionId: summary.sessionID.uuidString,
            locale: "en-US",
            transcript: summary.transcript,
            target: InsightTarget(
                durationSeconds: Int(summary.targetDurationSeconds),
                paceMinimumWpm: Int(summary.targetMinimumWPM.rounded()),
                paceMaximumWpm: Int(summary.targetMaximumWPM.rounded())
            ),
            metrics: InsightMetrics(
                durationSeconds: summary.durationSeconds,
                speakingSeconds: summary.speakingSeconds,
                averageWpm: boundedMetric(summary.averageWPM, lowerBound: 0, upperBound: 400),
                timeInPaceRangeRatio: summary.timeInPaceRange,
                fillerCount: summary.fillerCount,
                fillersPerMinute: boundedMetric(
                    summary.fillersPerSpeakingMinute,
                    lowerBound: 0,
                    upperBound: 100
                ),
                talkRatio: summary.talkRatio,
                paceStandardDeviationWpm: boundedOptionalMetric(
                    summary.paceStandardDeviationWPM,
                    lowerBound: 0,
                    upperBound: 200
                ),
                pauseCount: summary.pauseCount.map { min(max($0, 0), 10_000) },
                averagePauseSeconds: boundedOptionalMetric(
                    summary.averagePauseSeconds,
                    lowerBound: 0,
                    upperBound: 600
                ),
                longestPauseSeconds: boundedOptionalMetric(
                    summary.longestPauseSeconds,
                    lowerBound: 0,
                    upperBound: 7_200
                ),
                pitchRangeSemitones: summary.pitchRangeSemitones,
                energyRangeDb: summary.energyRangeDB,
                completedOnTime: summary.timingOutcome == .onTarget
                    && summary.durationSeconds <= summary.targetDurationSeconds
            ),
            checkpoints: checkpoints.map(InsightCheckpointRequest.init(result:)),
            cueEvents: cueEvents.map(InsightCueEventRequest.init(event:))
        )
        let response: InsightResponse = try await post(
            path: "/v1/insights",
            payload: payload,
            response: InsightResponse.self
        )
        guard response.schemaVersion == 1,
              !response.overallSummary.isEmpty,
              !response.strengths.isEmpty,
              !response.priorities.isEmpty,
              !response.drills.isEmpty else {
            throw VoxaAPIError.contractMismatch(requestID: nil)
        }
        return response.domainValue()
    }

    public func createRoadmap(
        summary: SessionSummary,
        history: LongTermAnalytics,
        fillerBreakdown: [FillerFrequency]
    ) async throws -> PracticeRoadmap {
        let trimmedTranscript = summary.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100_000).contains(trimmedTranscript.count),
              fillerBreakdownIsValid(
                  fillerBreakdown,
                  expectedTotal: summary.fillerCount
              ) else {
            throw VoxaAPIError.invalidPayload
        }
        let payload = RoadmapRequest(
            schemaVersion: 1,
            locale: "en-US",
            session: RoadmapSessionRequest(
                transcript: summary.transcript,
                target: insightTarget(summary: summary),
                metrics: insightMetrics(summary: summary),
                fillerBreakdown: fillerBreakdown.map(FillerFrequencyRequest.init(frequency:))
            ),
            history: RoadmapHistoryRequest(analytics: history)
        )
        let response: RoadmapResponse = try await post(
            path: "/v1/roadmaps",
            payload: payload,
            response: RoadmapResponse.self
        )
        guard response.isValid(fillerBreakdown: fillerBreakdown) else {
            throw VoxaAPIError.contractMismatch(requestID: nil)
        }
        return response.domainValue(fillerBreakdown: fillerBreakdown)
    }

    public func sendCoachMessage(
        summary: SessionSummary,
        fillerBreakdown: [FillerFrequency],
        roadmap: PracticeRoadmap,
        messages: [CoachMessage]
    ) async throws -> CoachReply {
        let trimmedTranscript = summary.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let roadmapResponse = RoadmapResponse(roadmap: roadmap)
        guard (1...100_000).contains(trimmedTranscript.count),
              fillerBreakdownIsValid(
                  fillerBreakdown,
                  expectedTotal: summary.fillerCount
              ),
              roadmapResponse.isValid(fillerBreakdown: fillerBreakdown),
              (1...10).contains(messages.count),
              messages.last?.role == .user,
              messages.allSatisfy({
                  let count = $0.content.trimmingCharacters(in: .whitespacesAndNewlines).count
                  return (1...1_000).contains(count)
              }) else {
            throw VoxaAPIError.invalidPayload
        }
        let payload = CoachChatRequest(
            schemaVersion: 1,
            locale: "en-US",
            session: RoadmapSessionRequest(
                transcript: summary.transcript,
                target: insightTarget(summary: summary),
                metrics: insightMetrics(summary: summary),
                fillerBreakdown: fillerBreakdown.map(FillerFrequencyRequest.init(frequency:))
            ),
            roadmap: roadmapResponse,
            messages: messages.map(CoachMessageRequest.init(message:))
        )
        let response: CoachReply = try await post(
            path: "/v1/coach-chat",
            payload: payload,
            response: CoachReply.self
        )
        guard response.schemaVersion == 1,
              !response.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              response.reply.count <= 1_200,
              response.suggestedPrompts.count <= 3,
              response.suggestedPrompts.allSatisfy({ !$0.isEmpty && $0.count <= 120 }) else {
            throw VoxaAPIError.contractMismatch(requestID: nil)
        }
        return response
    }

    private func get<Response: Decodable>(path: String, response: Response.Type) async throws -> Response {
        var request = try makeRequest(path: path, method: "GET")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request: request, response: response)
    }

    private func post<Request: Encodable, Response: Decodable>(
        path: String,
        payload: Request,
        response: Response.Type
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw VoxaAPIError.invalidPayload
        }
        return try await perform(request: request, response: response)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw VoxaAPIError.invalidPayload }
        var request = URLRequest(url: url, timeoutInterval: requestTimeoutSeconds)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Request-Id")
        return request
    }

    private func perform<Response: Decodable>(request: URLRequest, response: Response.Type) async throws -> Response {
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }
        guard let httpResponse = urlResponse as? HTTPURLResponse else { throw VoxaAPIError.invalidResponse }
        let requestID = httpResponse.value(forHTTPHeaderField: "X-Request-Id")
        guard data.count <= Self.maximumResponseBytes else {
            throw VoxaAPIError.contractMismatch(requestID: requestID)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw mapHTTPError(response: httpResponse, data: data, requestID: requestID)
        }
        guard httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json") == true else {
            throw VoxaAPIError.contractMismatch(requestID: requestID)
        }
        do {
            return try decoder.decode(response, from: data)
        } catch {
            throw VoxaAPIError.contractMismatch(requestID: requestID)
        }
    }

    private func mapTransportError(_ error: any Error) -> VoxaAPIError {
        if Task.isCancelled { return .cancelled }
        guard let urlError = error as? URLError else { return .transport }
        switch urlError.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut(requestID: nil)
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        default: return .transport
        }
    }

    private func mapHTTPError(response: HTTPURLResponse, data: Data, requestID: String?) -> VoxaAPIError {
        let errorBody = try? decoder.decode(APIErrorEnvelope.self, from: data).error
        let code = errorBody?.code ?? "request_failed"
        let message = errorBody?.message ?? "The coaching service could not complete the request."
        switch response.statusCode {
        case 401:
            return .unauthorized(requestID: requestID)
        case 429:
            return .rateLimited(
                retryAfterSeconds: response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init),
                requestID: requestID
            )
        case 503:
            return .unavailable(requestID: requestID)
        case 504:
            return .timedOut(requestID: requestID)
        default:
            return .rejected(
                statusCode: response.statusCode,
                code: code,
                message: message,
                requestID: requestID
            )
        }
    }
}

private func deckPlanIsValid(
    _ plan: DeckPlan,
    expectedTitle: String,
    targetDurationSeconds: Int,
    validSlideIndexes: Set<Int>
) -> Bool {
    guard plan.schemaVersion == 1,
          plan.title == expectedTitle,
          !plan.checkpoints.isEmpty,
          plan.checkpoints.count <= 100,
          plan.checkpoints.last?.targetCumulativeSeconds == targetDurationSeconds else {
        return false
    }
    var ids = Set<String>()
    var previousSlideIndex = -1
    var previousTarget = 0
    for checkpoint in plan.checkpoints {
        guard validSlideIndexes.contains(checkpoint.slideIndex),
              ids.insert(checkpoint.id).inserted,
              checkpoint.slideIndex > previousSlideIndex,
              checkpoint.targetCumulativeSeconds > previousTarget,
              !checkpoint.label.isEmpty,
              !checkpoint.semanticSummary.isEmpty,
              (2...12).contains(checkpoint.anchorTerms.count) else {
            return false
        }
        previousSlideIndex = checkpoint.slideIndex
        previousTarget = checkpoint.targetCumulativeSeconds
    }
    return true
}

private func boundedMetric(_ value: Double, lowerBound: Double, upperBound: Double) -> Double {
    min(max(value, lowerBound), upperBound)
}

private func boundedOptionalMetric(
    _ value: Double?,
    lowerBound: Double,
    upperBound: Double
) -> Double? {
    value.map { boundedMetric($0, lowerBound: lowerBound, upperBound: upperBound) }
}

private func normalizedFillerPhrase(_ phrase: String) -> String {
    phrase
        .split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
        .lowercased()
}

private func fillerBreakdownIsValid(
    _ fillerBreakdown: [FillerFrequency],
    expectedTotal: Int
) -> Bool {
    guard fillerBreakdown.count <= 20,
          fillerBreakdown.reduce(0, { $0 + $1.count }) == expectedTotal else {
        return false
    }
    var phrases = Set<String>()
    for filler in fillerBreakdown {
        let phrase = normalizedFillerPhrase(filler.phrase)
        guard (1...80).contains(phrase.count),
              (1...10_000).contains(filler.count),
              phrases.insert(phrase).inserted else {
            return false
        }
    }
    return true
}

private func insightTarget(summary: SessionSummary) -> InsightTarget {
    InsightTarget(
        durationSeconds: Int(summary.targetDurationSeconds),
        paceMinimumWpm: Int(summary.targetMinimumWPM.rounded()),
        paceMaximumWpm: Int(summary.targetMaximumWPM.rounded())
    )
}

private func insightMetrics(summary: SessionSummary) -> InsightMetrics {
    InsightMetrics(
        durationSeconds: summary.durationSeconds,
        speakingSeconds: summary.speakingSeconds,
        averageWpm: boundedMetric(summary.averageWPM, lowerBound: 0, upperBound: 400),
        timeInPaceRangeRatio: boundedMetric(summary.timeInPaceRange, lowerBound: 0, upperBound: 1),
        fillerCount: min(max(summary.fillerCount, 0), 10_000),
        fillersPerMinute: boundedMetric(summary.fillersPerSpeakingMinute, lowerBound: 0, upperBound: 100),
        talkRatio: boundedMetric(summary.talkRatio, lowerBound: 0, upperBound: 1),
        paceStandardDeviationWpm: boundedOptionalMetric(
            summary.paceStandardDeviationWPM,
            lowerBound: 0,
            upperBound: 200
        ),
        pauseCount: summary.pauseCount.map { min(max($0, 0), 10_000) },
        averagePauseSeconds: boundedOptionalMetric(
            summary.averagePauseSeconds,
            lowerBound: 0,
            upperBound: 600
        ),
        longestPauseSeconds: boundedOptionalMetric(
            summary.longestPauseSeconds,
            lowerBound: 0,
            upperBound: 7_200
        ),
        pitchRangeSemitones: boundedOptionalMetric(summary.pitchRangeSemitones, lowerBound: 0, upperBound: 96),
        energyRangeDb: boundedOptionalMetric(summary.energyRangeDB, lowerBound: 0, upperBound: 120),
        completedOnTime: summary.timingOutcome == .onTarget
            && summary.durationSeconds <= summary.targetDurationSeconds
    )
}

private struct DeckPlanRequest: Encodable {
    let schemaVersion: Int
    let locale: String
    let title: String
    let targetDurationSeconds: Int
    let slides: [DeckSlideRequest]
}

private struct DeckSlideRequest: Encodable {
    let slideIndex: Int
    let title: String
    let visibleText: String
    let speakerNotes: String
}

private struct InsightRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let locale: String
    let transcript: String
    let target: InsightTarget
    let metrics: InsightMetrics
    let checkpoints: [InsightCheckpointRequest]
    let cueEvents: [InsightCueEventRequest]
}

private struct InsightTarget: Encodable {
    let durationSeconds: Int
    let paceMinimumWpm: Int
    let paceMaximumWpm: Int
}

private struct InsightMetrics: Encodable {
    let durationSeconds: Double
    let speakingSeconds: Double
    let averageWpm: Double
    let timeInPaceRangeRatio: Double
    let fillerCount: Int
    let fillersPerMinute: Double
    let talkRatio: Double
    let paceStandardDeviationWpm: Double?
    let pauseCount: Int?
    let averagePauseSeconds: Double?
    let longestPauseSeconds: Double?
    let pitchRangeSemitones: Double?
    let energyRangeDb: Double?
    let completedOnTime: Bool

    private enum CodingKeys: String, CodingKey {
        case durationSeconds
        case speakingSeconds
        case averageWpm
        case timeInPaceRangeRatio
        case fillerCount
        case fillersPerMinute
        case talkRatio
        case paceStandardDeviationWpm
        case pauseCount
        case averagePauseSeconds
        case longestPauseSeconds
        case pitchRangeSemitones
        case energyRangeDb
        case completedOnTime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(speakingSeconds, forKey: .speakingSeconds)
        try container.encode(averageWpm, forKey: .averageWpm)
        try container.encode(timeInPaceRangeRatio, forKey: .timeInPaceRangeRatio)
        try container.encode(fillerCount, forKey: .fillerCount)
        try container.encode(fillersPerMinute, forKey: .fillersPerMinute)
        try container.encode(talkRatio, forKey: .talkRatio)
        try container.encode(paceStandardDeviationWpm, forKey: .paceStandardDeviationWpm)
        try container.encode(pauseCount, forKey: .pauseCount)
        try container.encode(averagePauseSeconds, forKey: .averagePauseSeconds)
        try container.encode(longestPauseSeconds, forKey: .longestPauseSeconds)
        if let pitchRangeSemitones {
            try container.encode(pitchRangeSemitones, forKey: .pitchRangeSemitones)
        } else {
            try container.encodeNil(forKey: .pitchRangeSemitones)
        }
        if let energyRangeDb {
            try container.encode(energyRangeDb, forKey: .energyRangeDb)
        } else {
            try container.encodeNil(forKey: .energyRangeDb)
        }
        try container.encode(completedOnTime, forKey: .completedOnTime)
    }
}

private struct InsightCheckpointRequest: Encodable {
    let id: String
    let label: String
    let targetCumulativeSeconds: Int
    let observedCumulativeSeconds: Double?
    let confidence: Double?
    let status: String

    init(result: SessionCheckpointResult) {
        self.id = result.id
        self.label = result.label
        self.targetCumulativeSeconds = result.targetCumulativeSeconds
        self.observedCumulativeSeconds = result.observedCumulativeSeconds
        self.confidence = result.confidence
        self.status = result.status.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case targetCumulativeSeconds
        case observedCumulativeSeconds
        case confidence
        case status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(targetCumulativeSeconds, forKey: .targetCumulativeSeconds)
        if let observedCumulativeSeconds {
            try container.encode(observedCumulativeSeconds, forKey: .observedCumulativeSeconds)
        } else {
            try container.encodeNil(forKey: .observedCumulativeSeconds)
        }
        if let confidence {
            try container.encode(confidence, forKey: .confidence)
        } else {
            try container.encodeNil(forKey: .confidence)
        }
        try container.encode(status, forKey: .status)
    }
}

private struct InsightCueEventRequest: Encodable {
    let sequence: UInt16?
    let kind: String
    let elapsedSeconds: Double
    let reason: String
    let deliveryStatus: String

    init(event: SessionCueEvent) {
        self.sequence = event.sequence
        self.kind = event.kind.apiName
        self.elapsedSeconds = event.elapsedSeconds
        self.reason = event.reason
        self.deliveryStatus = event.deliveryStatus.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case sequence
        case kind
        case elapsedSeconds
        case reason
        case deliveryStatus
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let sequence {
            try container.encode(sequence, forKey: .sequence)
        } else {
            try container.encodeNil(forKey: .sequence)
        }
        try container.encode(kind, forKey: .kind)
        try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        try container.encode(reason, forKey: .reason)
        try container.encode(deliveryStatus, forKey: .deliveryStatus)
    }
}

private struct InsightResponse: Decodable {
    let schemaVersion: Int
    let overallSummary: String
    let strengths: [EvidenceResponse]
    let priorities: [PriorityResponse]
    let drills: [DrillResponse]
    let confidenceNote: String

    func domainValue() -> CoachingInsight {
        CoachingInsight(
            schemaVersion: schemaVersion,
            overallSummary: overallSummary,
            strengths: strengths.map { EvidenceItem(id: UUID(), title: $0.title, evidence: $0.evidence) },
            priorities: priorities.map {
                CoachingPriority(id: UUID(), title: $0.title, evidence: $0.evidence, nextAction: $0.nextAction)
            },
            drills: drills.map {
                CoachingDrill(id: UUID(), title: $0.title, instructions: $0.instructions, durationMinutes: $0.durationMinutes)
            },
            confidenceNote: confidenceNote
        )
    }
}

private struct EvidenceResponse: Decodable {
    let title: String
    let evidence: String
}

private struct PriorityResponse: Decodable {
    let title: String
    let evidence: String
    let nextAction: String
}

private struct DrillResponse: Decodable {
    let title: String
    let instructions: String
    let durationMinutes: Int
}

private struct RoadmapRequest: Encodable {
    let schemaVersion: Int
    let locale: String
    let session: RoadmapSessionRequest
    let history: RoadmapHistoryRequest
}

private struct RoadmapSessionRequest: Encodable {
    let transcript: String
    let target: InsightTarget
    let metrics: InsightMetrics
    let fillerBreakdown: [FillerFrequencyRequest]
}

private struct FillerFrequencyRequest: Encodable {
    let phrase: String
    let count: Int

    init(frequency: FillerFrequency) {
        self.phrase = frequency.phrase
        self.count = frequency.count
    }
}

private struct RoadmapHistoryRequest: Encodable {
    let sessionCount: Int
    let totalPresentationSeconds: Double
    let averageWpm: Double
    let timeInPaceRangeRatio: Double
    let fillersPerMinute: Double
    let talkRatio: Double
    let onTargetSessionRatio: Double
    let averageAbsoluteTimingDeviationSeconds: Double
    let averagePaceStandardDeviationWpm: Double?
    let averagePitchRangeSemitones: Double?
    let averageEnergyRangeDb: Double?
    let measuredIntonationSessionCount: Int
    let pausesPerPresentationMinute: Double?
    let averagePauseSeconds: Double?
    let longestPauseSeconds: Double?
    let measuredPauseSessionCount: Int

    private enum CodingKeys: String, CodingKey {
        case sessionCount
        case totalPresentationSeconds
        case averageWpm
        case timeInPaceRangeRatio
        case fillersPerMinute
        case talkRatio
        case onTargetSessionRatio
        case averageAbsoluteTimingDeviationSeconds
        case averagePaceStandardDeviationWpm
        case averagePitchRangeSemitones
        case averageEnergyRangeDb
        case measuredIntonationSessionCount
        case pausesPerPresentationMinute
        case averagePauseSeconds
        case longestPauseSeconds
        case measuredPauseSessionCount
    }

    init(analytics: LongTermAnalytics) {
        self.sessionCount = min(max(analytics.sessionCount, 1), 1_000)
        self.totalPresentationSeconds = boundedMetric(
            analytics.totalPresentationSeconds,
            lowerBound: 1,
            upperBound: 7_200_000
        )
        self.averageWpm = boundedMetric(analytics.averageWPM, lowerBound: 0, upperBound: 400)
        self.timeInPaceRangeRatio = boundedMetric(analytics.timeInPaceRange, lowerBound: 0, upperBound: 1)
        self.fillersPerMinute = boundedMetric(analytics.fillersPerSpeakingMinute, lowerBound: 0, upperBound: 100)
        self.talkRatio = boundedMetric(analytics.talkRatio, lowerBound: 0, upperBound: 1)
        self.onTargetSessionRatio = boundedMetric(analytics.onTargetSessionRatio, lowerBound: 0, upperBound: 1)
        self.averageAbsoluteTimingDeviationSeconds = boundedMetric(
            analytics.averageAbsoluteTimingDeviationSeconds,
            lowerBound: 0,
            upperBound: 7_200
        )
        self.averagePaceStandardDeviationWpm = boundedOptionalMetric(
            analytics.averagePaceStandardDeviationWPM,
            lowerBound: 0,
            upperBound: 200
        )
        self.averagePitchRangeSemitones = boundedOptionalMetric(
            analytics.averagePitchRangeSemitones,
            lowerBound: 0,
            upperBound: 96
        )
        self.averageEnergyRangeDb = boundedOptionalMetric(
            analytics.averageEnergyRangeDB,
            lowerBound: 0,
            upperBound: 120
        )
        self.measuredIntonationSessionCount = min(max(analytics.measuredIntonationSessionCount, 0), self.sessionCount)
        self.pausesPerPresentationMinute = boundedOptionalMetric(
            analytics.pausesPerPresentationMinute,
            lowerBound: 0,
            upperBound: 600
        )
        self.averagePauseSeconds = boundedOptionalMetric(
            analytics.averagePauseSeconds,
            lowerBound: 0,
            upperBound: 600
        )
        self.longestPauseSeconds = boundedOptionalMetric(
            analytics.longestPauseSeconds,
            lowerBound: 0,
            upperBound: 7_200
        )
        self.measuredPauseSessionCount = min(max(analytics.measuredPauseSessionCount, 0), self.sessionCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionCount, forKey: .sessionCount)
        try container.encode(totalPresentationSeconds, forKey: .totalPresentationSeconds)
        try container.encode(averageWpm, forKey: .averageWpm)
        try container.encode(timeInPaceRangeRatio, forKey: .timeInPaceRangeRatio)
        try container.encode(fillersPerMinute, forKey: .fillersPerMinute)
        try container.encode(talkRatio, forKey: .talkRatio)
        try container.encode(onTargetSessionRatio, forKey: .onTargetSessionRatio)
        try container.encode(
            averageAbsoluteTimingDeviationSeconds,
            forKey: .averageAbsoluteTimingDeviationSeconds
        )
        try encodeOptional(
            averagePaceStandardDeviationWpm,
            forKey: .averagePaceStandardDeviationWpm,
            in: &container
        )
        try encodeOptional(
            averagePitchRangeSemitones,
            forKey: .averagePitchRangeSemitones,
            in: &container
        )
        try encodeOptional(
            averageEnergyRangeDb,
            forKey: .averageEnergyRangeDb,
            in: &container
        )
        try container.encode(measuredIntonationSessionCount, forKey: .measuredIntonationSessionCount)
        try encodeOptional(
            pausesPerPresentationMinute,
            forKey: .pausesPerPresentationMinute,
            in: &container
        )
        try encodeOptional(averagePauseSeconds, forKey: .averagePauseSeconds, in: &container)
        try encodeOptional(longestPauseSeconds, forKey: .longestPauseSeconds, in: &container)
        try container.encode(measuredPauseSessionCount, forKey: .measuredPauseSessionCount)
    }

    private func encodeOptional(
        _ value: Double?,
        forKey key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}

private struct RoadmapResponse: Codable {
    let schemaVersion: Int
    let headline: String
    let summary: String
    let focusFillers: [RoadmapFillerFocus]
    let steps: [RoadmapStep]
    let nextSessionGoal: RoadmapGoal
    let confidenceNote: String

    init(roadmap: PracticeRoadmap) {
        self.schemaVersion = roadmap.schemaVersion
        self.headline = roadmap.headline
        self.summary = roadmap.summary
        self.focusFillers = roadmap.focusFillers
        self.steps = roadmap.steps
        self.nextSessionGoal = roadmap.nextSessionGoal
        self.confidenceNote = roadmap.confidenceNote
    }

    func isValid(fillerBreakdown: [FillerFrequency]) -> Bool {
        let expectedCounts = fillerBreakdown.reduce(into: [String: Int]()) { counts, filler in
            counts[normalizedFillerPhrase(filler.phrase)] = filler.count
        }
        guard schemaVersion == 1,
              (1...100).contains(headline.count),
              (1...500).contains(summary.count),
              steps.map(\.phase) == RoadmapPhase.allCases,
              focusFillers.count <= 3,
              (1...100).contains(nextSessionGoal.title.count),
              (1...120).contains(nextSessionGoal.measurement.count),
              (1...180).contains(nextSessionGoal.target.count),
              (1...300).contains(confidenceNote.count) else {
            return false
        }
        var returnedPhrases = Set<String>()
        return focusFillers.allSatisfy { focus in
            let phrase = normalizedFillerPhrase(focus.phrase)
            return expectedCounts[phrase] == focus.count
                && returnedPhrases.insert(phrase).inserted
                && (1...300).contains(focus.guidance.count)
        } && steps.allSatisfy { step in
            (1...100).contains(step.title.count)
                && (1...300).contains(step.evidence.count)
                && (1...400).contains(step.action.count)
                && (1...240).contains(step.measurableTarget.count)
        }
    }

    func domainValue(fillerBreakdown: [FillerFrequency]) -> PracticeRoadmap {
        let canonicalPhrases = fillerBreakdown.reduce(into: [String: String]()) { phrases, filler in
            phrases[normalizedFillerPhrase(filler.phrase)] = filler.phrase
        }
        return PracticeRoadmap(
            schemaVersion: schemaVersion,
            headline: headline,
            summary: summary,
            focusFillers: focusFillers.map { focus in
                RoadmapFillerFocus(
                    phrase: canonicalPhrases[normalizedFillerPhrase(focus.phrase)] ?? focus.phrase,
                    count: focus.count,
                    guidance: focus.guidance
                )
            },
            steps: steps,
            nextSessionGoal: nextSessionGoal,
            confidenceNote: confidenceNote
        )
    }
}

private struct CoachChatRequest: Encodable {
    let schemaVersion: Int
    let locale: String
    let session: RoadmapSessionRequest
    let roadmap: RoadmapResponse
    let messages: [CoachMessageRequest]
}

private struct CoachMessageRequest: Encodable {
    let role: String
    let content: String

    init(message: CoachMessage) {
        self.role = message.role.rawValue
        self.content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
}

private struct APIErrorBody: Decodable {
    let code: String
    let message: String
}
