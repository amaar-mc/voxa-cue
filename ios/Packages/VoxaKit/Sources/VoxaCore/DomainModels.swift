import Foundation

public enum CueKind: UInt8, Codable, CaseIterable, Hashable, Sendable {
    case tooFast = 1
    case tooSlow = 2
    case fillerBurst = 3
    case deckBehind = 4
    case time75 = 5
    case time90 = 6
    case time100 = 7

    public static let liveMVP: [CueKind] = [
        .tooFast,
        .tooSlow,
        .fillerBurst,
        .time75,
        .time90,
        .time100,
    ]

    public var label: String {
        switch self {
        case .tooFast: "Slow down"
        case .tooSlow: "Pick up the pace"
        case .fillerBurst: "Reset fillers"
        case .deckBehind: "Move to the next idea"
        case .time75: "75% of time used"
        case .time90: "90% of time used"
        case .time100: "Target time reached"
        }
    }

    public var apiName: String {
        switch self {
        case .tooFast: "tooFast"
        case .tooSlow: "tooSlow"
        case .fillerBurst: "fillerBurst"
        case .deckBehind: "deckBehind"
        case .time75: "time75"
        case .time90: "time90"
        case .time100: "time100"
        }
    }
}

public enum CueIntensity: UInt8, Codable, CaseIterable, Hashable, Sendable {
    case soft = 0
    case medium = 1
    case strong = 2

    public var label: String {
        switch self {
        case .soft: "Soft"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }
}

public enum SessionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case freeSpeaking
    case powerPoint

    public var label: String {
        switch self {
        case .freeSpeaking: "Free speaking"
        case .powerPoint: "PowerPoint"
        }
    }
}

public struct CueCommand: Codable, Equatable, Sendable {
    public let sequence: UInt16
    public let kind: CueKind
    public let intensity: CueIntensity
    public let repeatCount: UInt8

    public init(sequence: UInt16, kind: CueKind, intensity: CueIntensity, repeatCount: UInt8) {
        self.sequence = sequence
        self.kind = kind
        self.intensity = intensity
        self.repeatCount = repeatCount
    }
}

public struct CoachingProfile: Codable, Equatable, Sendable {
    public let minimumWPM: Double
    public let maximumWPM: Double
    public let enabledCues: Set<CueKind>
    public let intensityByCue: [CueKind: CueIntensity]
    public let highConfidenceFillers: [String]
    public let optionalFillers: [String]

    public init(
        minimumWPM: Double,
        maximumWPM: Double,
        enabledCues: Set<CueKind>,
        intensityByCue: [CueKind: CueIntensity],
        highConfidenceFillers: [String],
        optionalFillers: [String]
    ) {
        self.minimumWPM = minimumWPM
        self.maximumWPM = maximumWPM
        self.enabledCues = enabledCues
        self.intensityByCue = intensityByCue
        self.highConfidenceFillers = highConfidenceFillers
        self.optionalFillers = optionalFillers
    }

    public static func rehearsalV1() -> CoachingProfile {
        CoachingProfile(
            minimumWPM: 130,
            maximumWPM: 160,
            enabledCues: Set(CueKind.liveMVP),
            intensityByCue: Dictionary(uniqueKeysWithValues: CueKind.liveMVP.map { ($0, .medium) }),
            highConfidenceFillers: ["um", "uh", "er", "erm", "you know"],
            optionalFillers: ["like", "actually", "basically", "literally", "i mean", "sort of", "kind of"]
        )
    }
}

public struct SessionConfiguration: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let mode: SessionMode
    public let targetDurationSeconds: TimeInterval
    public let profile: CoachingProfile
    public let deckPlan: DeckPlan?

    public init(
        id: UUID,
        name: String,
        mode: SessionMode,
        targetDurationSeconds: TimeInterval,
        profile: CoachingProfile,
        deckPlan: DeckPlan?
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.targetDurationSeconds = targetDurationSeconds
        self.profile = profile
        self.deckPlan = deckPlan
    }
}

public struct FinalTranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval
    public let text: String

    public init(id: UUID, startSeconds: TimeInterval, endSeconds: TimeInterval, text: String) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
    }
}

public struct TimedWord: Codable, Equatable, Sendable {
    public let text: String
    public let endSeconds: TimeInterval

    public init(text: String, endSeconds: TimeInterval) {
        self.text = text
        self.endSeconds = endSeconds
    }
}

public struct DeckSlide: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let index: Int
    public let title: String
    public let body: String
    public let notes: String

    public init(id: UUID, index: Int, title: String, body: String, notes: String) {
        self.id = id
        self.index = index
        self.title = title
        self.body = body
        self.notes = notes
    }
}

public struct DeckCheckpoint: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let slideIndex: Int
    public let label: String
    public let targetCumulativeSeconds: Int
    public let semanticSummary: String
    public let anchorTerms: [String]

    public init(
        id: String,
        slideIndex: Int,
        label: String,
        targetCumulativeSeconds: Int,
        semanticSummary: String,
        anchorTerms: [String]
    ) {
        self.id = id
        self.slideIndex = slideIndex
        self.label = label
        self.targetCumulativeSeconds = targetCumulativeSeconds
        self.semanticSummary = semanticSummary
        self.anchorTerms = anchorTerms
    }
}

public struct DeckPlan: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let title: String
    public let checkpoints: [DeckCheckpoint]

    public init(schemaVersion: Int, title: String, checkpoints: [DeckCheckpoint]) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.checkpoints = checkpoints
    }
}

public struct LiveMetrics: Codable, Equatable, Sendable {
    public let elapsedSeconds: TimeInterval
    public let rollingWPM: Double
    public let finalizedWordCount: Int
    public let fillerCount: Int
    public let voicedSeconds: TimeInterval
    public let talkRatio: Double
    public let energyDBFS: Double?
    public let pitchHertz: Double?

    public init(
        elapsedSeconds: TimeInterval,
        rollingWPM: Double,
        finalizedWordCount: Int,
        fillerCount: Int,
        voicedSeconds: TimeInterval,
        talkRatio: Double,
        energyDBFS: Double?,
        pitchHertz: Double?
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.rollingWPM = rollingWPM
        self.finalizedWordCount = finalizedWordCount
        self.fillerCount = fillerCount
        self.voicedSeconds = voicedSeconds
        self.talkRatio = talkRatio
        self.energyDBFS = energyDBFS
        self.pitchHertz = pitchHertz
    }

    public static func empty() -> LiveMetrics {
        LiveMetrics(
            elapsedSeconds: 0,
            rollingWPM: 0,
            finalizedWordCount: 0,
            fillerCount: 0,
            voicedSeconds: 0,
            talkRatio: 0,
            energyDBFS: nil,
            pitchHertz: nil
        )
    }
}

public struct SessionSummary: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let name: String
    public let startedAt: Date
    public let durationSeconds: TimeInterval
    public let targetDurationSeconds: TimeInterval
    public let targetMinimumWPM: Double
    public let targetMaximumWPM: Double
    public let speakingSeconds: TimeInterval
    public let averageWPM: Double
    public let timeInPaceRange: Double
    public let fillerCount: Int
    public let fillersPerSpeakingMinute: Double
    public let talkRatio: Double
    public let pitchRangeSemitones: Double?
    public let energyRangeDB: Double?
    public let cueCount: Int
    public let transcript: String

    public init(
        sessionID: UUID,
        name: String,
        startedAt: Date,
        durationSeconds: TimeInterval,
        targetDurationSeconds: TimeInterval,
        targetMinimumWPM: Double,
        targetMaximumWPM: Double,
        speakingSeconds: TimeInterval,
        averageWPM: Double,
        timeInPaceRange: Double,
        fillerCount: Int,
        fillersPerSpeakingMinute: Double,
        talkRatio: Double,
        pitchRangeSemitones: Double?,
        energyRangeDB: Double?,
        cueCount: Int,
        transcript: String
    ) {
        self.sessionID = sessionID
        self.name = name
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.targetDurationSeconds = targetDurationSeconds
        self.targetMinimumWPM = targetMinimumWPM
        self.targetMaximumWPM = targetMaximumWPM
        self.speakingSeconds = speakingSeconds
        self.averageWPM = averageWPM
        self.timeInPaceRange = timeInPaceRange
        self.fillerCount = fillerCount
        self.fillersPerSpeakingMinute = fillersPerSpeakingMinute
        self.talkRatio = talkRatio
        self.pitchRangeSemitones = pitchRangeSemitones
        self.energyRangeDB = energyRangeDB
        self.cueCount = cueCount
        self.transcript = transcript
    }
}

public enum CheckpointOutcomeStatus: String, Codable, Equatable, Sendable {
    case reached
    case missed
    case skipped
}

public enum CueDeliveryStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case completed
    case failed
    case notConnected
    case suppressed
}

public struct SessionCheckpointResult: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let targetCumulativeSeconds: Int
    public let observedCumulativeSeconds: Double?
    public let confidence: Double?
    public let status: CheckpointOutcomeStatus

    public init(
        id: String,
        label: String,
        targetCumulativeSeconds: Int,
        observedCumulativeSeconds: Double?,
        confidence: Double?,
        status: CheckpointOutcomeStatus
    ) {
        self.id = id
        self.label = label
        self.targetCumulativeSeconds = targetCumulativeSeconds
        self.observedCumulativeSeconds = observedCumulativeSeconds
        self.confidence = confidence
        self.status = status
    }
}

public struct SessionCueEvent: Codable, Equatable, Sendable {
    public let sequence: UInt16?
    public let kind: CueKind
    public let elapsedSeconds: TimeInterval
    public let reason: String
    public let deliveryStatus: CueDeliveryStatus

    public init(
        sequence: UInt16?,
        kind: CueKind,
        elapsedSeconds: TimeInterval,
        reason: String,
        deliveryStatus: CueDeliveryStatus
    ) {
        self.sequence = sequence
        self.kind = kind
        self.elapsedSeconds = elapsedSeconds
        self.reason = reason
        self.deliveryStatus = deliveryStatus
    }
}

public struct EvidenceItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let evidence: String

    public init(id: UUID, title: String, evidence: String) {
        self.id = id
        self.title = title
        self.evidence = evidence
    }
}

public struct CoachingPriority: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let evidence: String
    public let nextAction: String

    public init(id: UUID, title: String, evidence: String, nextAction: String) {
        self.id = id
        self.title = title
        self.evidence = evidence
        self.nextAction = nextAction
    }
}

public struct CoachingDrill: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let instructions: String
    public let durationMinutes: Int

    public init(id: UUID, title: String, instructions: String, durationMinutes: Int) {
        self.id = id
        self.title = title
        self.instructions = instructions
        self.durationMinutes = durationMinutes
    }
}

public struct CoachingInsight: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let overallSummary: String
    public let strengths: [EvidenceItem]
    public let priorities: [CoachingPriority]
    public let drills: [CoachingDrill]
    public let confidenceNote: String

    public init(
        schemaVersion: Int,
        overallSummary: String,
        strengths: [EvidenceItem],
        priorities: [CoachingPriority],
        drills: [CoachingDrill],
        confidenceNote: String
    ) {
        self.schemaVersion = schemaVersion
        self.overallSummary = overallSummary
        self.strengths = strengths
        self.priorities = priorities
        self.drills = drills
        self.confidenceNote = confidenceNote
    }
}
