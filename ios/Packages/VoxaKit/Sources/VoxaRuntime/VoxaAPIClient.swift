import Foundation
import VoxaCore

public enum VoxaAPIError: Error, Equatable {
    case invalidResponse
    case rejected(statusCode: Int, message: String)
    case invalidPayload
}

public actor VoxaAPIClient {
    private let baseURL: URL
    private let bearerToken: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, bearerToken: String, session: URLSession) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
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
        let response: DeckPlan = try await post(path: "/v1/deck-plans", payload: payload, response: DeckPlan.self)
        return response
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
                completedOnTime: summary.durationSeconds <= summary.targetDurationSeconds
            ),
            checkpoints: checkpoints.map(InsightCheckpointRequest.init(result:)),
            cueEvents: cueEvents.map(InsightCueEventRequest.init(event:))
        )
        let response: InsightResponse = try await post(
            path: "/v1/insights",
            payload: payload,
            response: InsightResponse.self
        )
        return response.domainValue()
    }

    private func post<Request: Encodable, Response: Decodable>(
        path: String,
        payload: Request,
        response: Response.Type
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw VoxaAPIError.invalidPayload }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)
        let (data, urlResponse) = try await session.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else { throw VoxaAPIError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? decoder.decode(APIErrorEnvelope.self, from: data).error.message) ?? "Request failed"
            throw VoxaAPIError.rejected(statusCode: httpResponse.statusCode, message: message)
        }
        return try decoder.decode(response, from: data)
    }
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
