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

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
}

private struct APIErrorBody: Decodable {
    let code: String
    let message: String
}
