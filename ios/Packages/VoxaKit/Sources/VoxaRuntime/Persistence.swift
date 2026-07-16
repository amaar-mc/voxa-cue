import Foundation
import SwiftData
import VoxaCore

@Model
public final class SessionRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var startedAt: Date
    public var durationSeconds: Double
    public var targetDurationSeconds: Double
    public var targetMinimumWPM: Double
    public var targetMaximumWPM: Double
    public var speakingSeconds: Double
    public var averageWPM: Double
    public var timeInPaceRange: Double
    public var fillerCount: Int
    public var fillersPerSpeakingMinute: Double
    public var talkRatio: Double
    public var pitchRangeSemitones: Double?
    public var energyRangeDB: Double?
    public var cueCount: Int
    public var transcript: String

    public init(summary: SessionSummary) {
        self.id = summary.sessionID
        self.name = summary.name
        self.startedAt = summary.startedAt
        self.durationSeconds = summary.durationSeconds
        self.targetDurationSeconds = summary.targetDurationSeconds
        self.targetMinimumWPM = summary.targetMinimumWPM
        self.targetMaximumWPM = summary.targetMaximumWPM
        self.speakingSeconds = summary.speakingSeconds
        self.averageWPM = summary.averageWPM
        self.timeInPaceRange = summary.timeInPaceRange
        self.fillerCount = summary.fillerCount
        self.fillersPerSpeakingMinute = summary.fillersPerSpeakingMinute
        self.talkRatio = summary.talkRatio
        self.pitchRangeSemitones = summary.pitchRangeSemitones
        self.energyRangeDB = summary.energyRangeDB
        self.cueCount = summary.cueCount
        self.transcript = summary.transcript
    }

    public func summaryValue() -> SessionSummary {
        SessionSummary(
            sessionID: id,
            name: name,
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            targetDurationSeconds: targetDurationSeconds,
            targetMinimumWPM: targetMinimumWPM,
            targetMaximumWPM: targetMaximumWPM,
            speakingSeconds: speakingSeconds,
            averageWPM: averageWPM,
            timeInPaceRange: timeInPaceRange,
            fillerCount: fillerCount,
            fillersPerSpeakingMinute: fillersPerSpeakingMinute,
            talkRatio: talkRatio,
            pitchRangeSemitones: pitchRangeSemitones,
            energyRangeDB: energyRangeDB,
            cueCount: cueCount,
            transcript: transcript
        )
    }
}

@Model
public final class TranscriptSegmentRecord {
    @Attribute(.unique) public var id: UUID
    public var sessionID: UUID
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String

    public init(segment: FinalTranscriptSegment, sessionID: UUID) {
        self.id = segment.id
        self.sessionID = sessionID
        self.startSeconds = segment.startSeconds
        self.endSeconds = segment.endSeconds
        self.text = segment.text
    }
}

@Model
public final class MetricSampleRecord {
    @Attribute(.unique) public var id: UUID
    public var sessionID: UUID
    public var elapsedSeconds: Double
    public var rollingWPM: Double
    public var fillerCount: Int
    public var voicedSeconds: Double
    public var talkRatio: Double
    public var energyDBFS: Double?
    public var pitchHertz: Double?

    public init(id: UUID, sessionID: UUID, metrics: LiveMetrics) {
        self.id = id
        self.sessionID = sessionID
        self.elapsedSeconds = metrics.elapsedSeconds
        self.rollingWPM = metrics.rollingWPM
        self.fillerCount = metrics.fillerCount
        self.voicedSeconds = metrics.voicedSeconds
        self.talkRatio = metrics.talkRatio
        self.energyDBFS = metrics.energyDBFS
        self.pitchHertz = metrics.pitchHertz
    }
}

@Model
public final class CueEventRecord {
    @Attribute(.unique) public var id: UUID
    public var sessionID: UUID
    public var sequence: Int?
    public var kindRawValue: UInt8
    public var reason: String
    public var elapsedSeconds: Double
    public var deliveryStatusRawValue: String

    public init(id: UUID, sessionID: UUID, event: SessionCueEvent) {
        self.id = id
        self.sessionID = sessionID
        self.sequence = event.sequence.map(Int.init)
        self.kindRawValue = event.kind.rawValue
        self.reason = event.reason
        self.elapsedSeconds = event.elapsedSeconds
        self.deliveryStatusRawValue = event.deliveryStatus.rawValue
    }

    public func value() -> SessionCueEvent? {
        guard let kind = CueKind(rawValue: kindRawValue),
              let deliveryStatus = CueDeliveryStatus(rawValue: deliveryStatusRawValue) else {
            return nil
        }
        return SessionCueEvent(
            sequence: sequence.flatMap(UInt16.init(exactly:)),
            kind: kind,
            elapsedSeconds: elapsedSeconds,
            reason: reason,
            deliveryStatus: deliveryStatus
        )
    }
}

@Model
public final class CheckpointResultRecord {
    @Attribute(.unique) public var id: UUID
    public var sessionID: UUID
    public var checkpointID: String
    public var label: String
    public var targetCumulativeSeconds: Int
    public var observedCumulativeSeconds: Double?
    public var confidence: Double?
    public var statusRawValue: String

    public init(id: UUID, sessionID: UUID, result: SessionCheckpointResult) {
        self.id = id
        self.sessionID = sessionID
        self.checkpointID = result.id
        self.label = result.label
        self.targetCumulativeSeconds = result.targetCumulativeSeconds
        self.observedCumulativeSeconds = result.observedCumulativeSeconds
        self.confidence = result.confidence
        self.statusRawValue = result.status.rawValue
    }

    public func value() -> SessionCheckpointResult? {
        guard let status = CheckpointOutcomeStatus(rawValue: statusRawValue) else { return nil }
        return SessionCheckpointResult(
            id: checkpointID,
            label: label,
            targetCumulativeSeconds: targetCumulativeSeconds,
            observedCumulativeSeconds: observedCumulativeSeconds,
            confidence: confidence,
            status: status
        )
    }
}

@Model
public final class DeckRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var slidesData: Data
    public var planData: Data

    public init(id: UUID, title: String, createdAt: Date, slidesData: Data, planData: Data) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.slidesData = slidesData
        self.planData = planData
    }
}

@Model
public final class InsightRecord {
    @Attribute(.unique) public var id: UUID
    public var sessionID: UUID
    public var generatedAt: Date
    public var insightData: Data

    public init(id: UUID, sessionID: UUID, generatedAt: Date, insightData: Data) {
        self.id = id
        self.sessionID = sessionID
        self.generatedAt = generatedAt
        self.insightData = insightData
    }
}

@MainActor
public final class VoxaDataStore {
    public let container: ModelContainer
    public let isInMemory: Bool
    public var context: ModelContext { container.mainContext }
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(inMemory: Bool) throws {
        let schema = Schema([
            SessionRecord.self,
            TranscriptSegmentRecord.self,
            MetricSampleRecord.self,
            CueEventRecord.self,
            CheckpointResultRecord.self,
            DeckRecord.self,
            InsightRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        self.container = try ModelContainer(for: schema, configurations: [configuration])
        self.isInMemory = inMemory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func saveSession(
        summary: SessionSummary,
        segments: [FinalTranscriptSegment],
        samples: [LiveMetrics],
        cueEvents: [SessionCueEvent],
        checkpointResults: [SessionCheckpointResult]
    ) throws {
        context.insert(SessionRecord(summary: summary))
        for segment in segments {
            context.insert(TranscriptSegmentRecord(segment: segment, sessionID: summary.sessionID))
        }
        for sample in samples {
            context.insert(MetricSampleRecord(id: UUID(), sessionID: summary.sessionID, metrics: sample))
        }
        for event in cueEvents {
            context.insert(CueEventRecord(id: UUID(), sessionID: summary.sessionID, event: event))
        }
        for result in checkpointResults {
            context.insert(CheckpointResultRecord(id: UUID(), sessionID: summary.sessionID, result: result))
        }
        try context.save()
    }

    public func fetchSessions() throws -> [SessionSummary] {
        let descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return try context.fetch(descriptor).map { $0.summaryValue() }
    }

    public func saveDeck(id: UUID, title: String, slides: [DeckSlide], plan: DeckPlan) throws {
        let record = DeckRecord(
            id: id,
            title: title,
            createdAt: Date(),
            slidesData: try encoder.encode(slides),
            planData: try encoder.encode(plan)
        )
        context.insert(record)
        try context.save()
    }

    public func saveInsight(sessionID: UUID, insight: CoachingInsight) throws {
        context.insert(
            InsightRecord(
                id: UUID(),
                sessionID: sessionID,
                generatedAt: Date(),
                insightData: try encoder.encode(insight)
            )
        )
        try context.save()
    }

    public func fetchInsight(sessionID: UUID) throws -> CoachingInsight? {
        let descriptor = FetchDescriptor<InsightRecord>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        guard let data = try context.fetch(descriptor).first?.insightData else { return nil }
        return try decoder.decode(CoachingInsight.self, from: data)
    }

    public func fetchInsightContext(sessionID: UUID) throws -> SessionInsightContext {
        let cueDescriptor = FetchDescriptor<CueEventRecord>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.elapsedSeconds)]
        )
        let checkpointDescriptor = FetchDescriptor<CheckpointResultRecord>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.targetCumulativeSeconds)]
        )
        return SessionInsightContext(
            checkpoints: try context.fetch(checkpointDescriptor).compactMap { $0.value() },
            cueEvents: try context.fetch(cueDescriptor).compactMap { $0.value() }
        )
    }

    public func deleteAllLocalData() throws {
        try context.delete(model: SessionRecord.self)
        try context.delete(model: TranscriptSegmentRecord.self)
        try context.delete(model: MetricSampleRecord.self)
        try context.delete(model: CueEventRecord.self)
        try context.delete(model: CheckpointResultRecord.self)
        try context.delete(model: DeckRecord.self)
        try context.delete(model: InsightRecord.self)
        try context.save()
    }
}

public struct SessionInsightContext: Equatable, Sendable {
    public let checkpoints: [SessionCheckpointResult]
    public let cueEvents: [SessionCueEvent]

    public init(checkpoints: [SessionCheckpointResult], cueEvents: [SessionCueEvent]) {
        self.checkpoints = checkpoints
        self.cueEvents = cueEvents
    }
}
