import Foundation

public struct CueEngineConfiguration: Equatable, Sendable {
    public let paceWindowSeconds: TimeInterval
    public let minimumVoicedSeconds: TimeInterval
    public let minimumRecognizedWords: Int
    public let paceTranscriptFreshnessSeconds: TimeInterval
    public let paceHysteresisWPM: Double
    public let paceEvaluationIntervalSeconds: TimeInterval
    public let fastPersistenceSeconds: TimeInterval
    public let slowPersistenceSeconds: TimeInterval
    public let perRuleCooldownSeconds: TimeInterval
    public let deckCooldownSeconds: TimeInterval
    public let globalCooldownSeconds: TimeInterval
    public let deckGraceSeconds: TimeInterval
    public let deckMinimumConfidence: Double

    public init(
        paceWindowSeconds: TimeInterval,
        minimumVoicedSeconds: TimeInterval,
        minimumRecognizedWords: Int,
        paceTranscriptFreshnessSeconds: TimeInterval,
        paceHysteresisWPM: Double,
        paceEvaluationIntervalSeconds: TimeInterval,
        fastPersistenceSeconds: TimeInterval,
        slowPersistenceSeconds: TimeInterval,
        perRuleCooldownSeconds: TimeInterval,
        deckCooldownSeconds: TimeInterval,
        globalCooldownSeconds: TimeInterval,
        deckGraceSeconds: TimeInterval,
        deckMinimumConfidence: Double
    ) {
        self.paceWindowSeconds = paceWindowSeconds
        self.minimumVoicedSeconds = minimumVoicedSeconds
        self.minimumRecognizedWords = minimumRecognizedWords
        self.paceTranscriptFreshnessSeconds = paceTranscriptFreshnessSeconds
        self.paceHysteresisWPM = paceHysteresisWPM
        self.paceEvaluationIntervalSeconds = paceEvaluationIntervalSeconds
        self.fastPersistenceSeconds = fastPersistenceSeconds
        self.slowPersistenceSeconds = slowPersistenceSeconds
        self.perRuleCooldownSeconds = perRuleCooldownSeconds
        self.deckCooldownSeconds = deckCooldownSeconds
        self.globalCooldownSeconds = globalCooldownSeconds
        self.deckGraceSeconds = deckGraceSeconds
        self.deckMinimumConfidence = deckMinimumConfidence
    }

    public static func version1() -> CueEngineConfiguration {
        CueEngineConfiguration(
            paceWindowSeconds: 8,
            minimumVoicedSeconds: 2,
            minimumRecognizedWords: 4,
            paceTranscriptFreshnessSeconds: 4,
            paceHysteresisWPM: 5,
            paceEvaluationIntervalSeconds: 3,
            fastPersistenceSeconds: 4,
            slowPersistenceSeconds: 5,
            perRuleCooldownSeconds: 30,
            deckCooldownSeconds: 45,
            globalCooldownSeconds: 12,
            deckGraceSeconds: 15,
            deckMinimumConfidence: 0.70
        )
    }
}

public struct PaceEvidence: Equatable, Sendable {
    public let recognizedWordCount: Int
    public let latestTranscriptEndSeconds: TimeInterval?

    public init(recognizedWordCount: Int, latestTranscriptEndSeconds: TimeInterval?) {
        self.recognizedWordCount = recognizedWordCount
        self.latestTranscriptEndSeconds = latestTranscriptEndSeconds
    }
}

public enum DeckCuePolicy: Equatable, Sendable {
    case semanticAlignment
    case scheduledTransition
}

public struct DeckProgress: Equatable, Sendable {
    public let checkpointID: String
    public let targetCumulativeSeconds: TimeInterval
    public let reached: Bool
    public let confidence: Double
    public let policy: DeckCuePolicy

    public init(
        checkpointID: String,
        targetCumulativeSeconds: TimeInterval,
        reached: Bool,
        confidence: Double,
        policy: DeckCuePolicy
    ) {
        self.checkpointID = checkpointID
        self.targetCumulativeSeconds = targetCumulativeSeconds
        self.reached = reached
        self.confidence = confidence
        self.policy = policy
    }
}

public struct CueEvaluationInput: Equatable, Sendable {
    public let metrics: LiveMetrics
    public let paceEvidence: PaceEvidence
    public let targetDurationSeconds: TimeInterval
    public let recentFillerOffsets: [TimeInterval]
    public let deckProgress: DeckProgress?
    public let profile: CoachingProfile
    public let isPaused: Bool

    public init(
        metrics: LiveMetrics,
        paceEvidence: PaceEvidence,
        targetDurationSeconds: TimeInterval,
        recentFillerOffsets: [TimeInterval],
        deckProgress: DeckProgress?,
        profile: CoachingProfile,
        isPaused: Bool
    ) {
        self.metrics = metrics
        self.paceEvidence = paceEvidence
        self.targetDurationSeconds = targetDurationSeconds
        self.recentFillerOffsets = recentFillerOffsets
        self.deckProgress = deckProgress
        self.profile = profile
        self.isPaused = isPaused
    }
}

public struct CueEngineState: Equatable, Sendable {
    public let fastConditionStartedAt: TimeInterval?
    public let slowConditionStartedAt: TimeInterval?
    public let fastConditionArmed: Bool
    public let slowConditionArmed: Bool
    public let lastPaceEvaluationAt: TimeInterval?
    public let lastGlobalCueAt: TimeInterval?
    public let lastCueAtByKind: [CueKind: TimeInterval]
    public let deliveredMilestones: Set<CueKind>
    public let deliveredDeckCheckpoints: Set<String>

    public init(
        fastConditionStartedAt: TimeInterval?,
        slowConditionStartedAt: TimeInterval?,
        fastConditionArmed: Bool,
        slowConditionArmed: Bool,
        lastPaceEvaluationAt: TimeInterval?,
        lastGlobalCueAt: TimeInterval?,
        lastCueAtByKind: [CueKind: TimeInterval],
        deliveredMilestones: Set<CueKind>,
        deliveredDeckCheckpoints: Set<String>
    ) {
        self.fastConditionStartedAt = fastConditionStartedAt
        self.slowConditionStartedAt = slowConditionStartedAt
        self.fastConditionArmed = fastConditionArmed
        self.slowConditionArmed = slowConditionArmed
        self.lastPaceEvaluationAt = lastPaceEvaluationAt
        self.lastGlobalCueAt = lastGlobalCueAt
        self.lastCueAtByKind = lastCueAtByKind
        self.deliveredMilestones = deliveredMilestones
        self.deliveredDeckCheckpoints = deliveredDeckCheckpoints
    }

    public static func initial() -> CueEngineState {
        CueEngineState(
            fastConditionStartedAt: nil,
            slowConditionStartedAt: nil,
            fastConditionArmed: true,
            slowConditionArmed: true,
            lastPaceEvaluationAt: nil,
            lastGlobalCueAt: nil,
            lastCueAtByKind: [:],
            deliveredMilestones: [],
            deliveredDeckCheckpoints: []
        )
    }
}

public struct CueDecision: Equatable, Sendable {
    public let kind: CueKind
    public let reason: String

    public init(kind: CueKind, reason: String) {
        self.kind = kind
        self.reason = reason
    }
}

public struct CueEvaluationResult: Equatable, Sendable {
    public let state: CueEngineState
    public let decision: CueDecision?

    public init(state: CueEngineState, decision: CueDecision?) {
        self.state = state
        self.decision = decision
    }
}

public func evaluateCue(
    input: CueEvaluationInput,
    state: CueEngineState,
    configuration: CueEngineConfiguration
) -> CueEvaluationResult {
    let elapsed = input.metrics.elapsedSeconds
    guard !input.isPaused else {
        return CueEvaluationResult(
            state: suspendPaceCuePersistence(state: state),
            decision: nil
        )
    }

    let paceEvidenceIsUsable = paceEvidenceIsUsable(
        input: input,
        configuration: configuration
    )
    var fastStart = paceEvidenceIsUsable ? state.fastConditionStartedAt : nil
    var slowStart = paceEvidenceIsUsable ? state.slowConditionStartedAt : nil
    var fastArmed = state.fastConditionArmed
    var slowArmed = state.slowConditionArmed
    let paceEvaluationIsDue = state.lastPaceEvaluationAt.map {
        (elapsed - $0) >= configuration.paceEvaluationIntervalSeconds
    } ?? (elapsed >= configuration.paceEvaluationIntervalSeconds)
    let lastPaceEvaluationAt = paceEvaluationIsDue ? elapsed : state.lastPaceEvaluationAt

    if paceEvaluationIsDue, paceEvidenceIsUsable {
        if input.metrics.rollingWPM > input.profile.maximumWPM, fastArmed {
            fastStart = fastStart ?? elapsed
        } else if input.metrics.rollingWPM < input.profile.maximumWPM - configuration.paceHysteresisWPM {
            fastStart = nil
            fastArmed = true
        }

        if input.metrics.rollingWPM > 0,
           input.metrics.rollingWPM < input.profile.minimumWPM,
           slowArmed {
            slowStart = slowStart ?? elapsed
        } else if input.metrics.rollingWPM > input.profile.minimumWPM + configuration.paceHysteresisWPM {
            slowStart = nil
            slowArmed = true
        }
    } else if paceEvaluationIsDue {
        fastStart = nil
        slowStart = nil
    }
    let conditionedState = CueEngineState(
        fastConditionStartedAt: fastStart,
        slowConditionStartedAt: slowStart,
        fastConditionArmed: fastArmed,
        slowConditionArmed: slowArmed,
        lastPaceEvaluationAt: lastPaceEvaluationAt,
        lastGlobalCueAt: state.lastGlobalCueAt,
        lastCueAtByKind: state.lastCueAtByKind,
        deliveredMilestones: state.deliveredMilestones,
        deliveredDeckCheckpoints: state.deliveredDeckCheckpoints
    )

    let candidates = orderedCandidates(
        input: input,
        state: conditionedState,
        configuration: configuration,
        paceEvaluationIsDue: paceEvaluationIsDue
    )
    guard let decision = candidates.first(where: { candidate in
        input.profile.enabledCues.contains(candidate.kind)
            && ruleCooldownPassed(
                kind: candidate.kind,
                elapsed: elapsed,
                state: conditionedState,
                deckPolicy: input.deckProgress?.policy,
                configuration: configuration
            )
    }) else {
        return CueEvaluationResult(state: conditionedState, decision: nil)
    }
    guard isTimeMilestone(decision.kind)
            || isScheduledTransition(decision: decision, input: input)
            || globalCooldownPassed(
                elapsed: elapsed,
                state: conditionedState,
                seconds: configuration.globalCooldownSeconds
            ) else {
        return CueEvaluationResult(state: conditionedState, decision: nil)
    }

    var lastByKind = conditionedState.lastCueAtByKind
    lastByKind[decision.kind] = elapsed
    var milestones = conditionedState.deliveredMilestones
    switch decision.kind {
    case .time50:
        milestones.insert(decision.kind)
    case .time75:
        milestones.formUnion([.time50, .time75])
    case .time90:
        milestones.formUnion([.time50, .time75, .time90])
    case .time100:
        milestones.formUnion([.time50, .time75, .time90, .time100])
    case .tooFast, .tooSlow, .fillerBurst, .deckBehind:
        break
    }
    if isScheduledTransition(decision: decision, input: input) {
        milestones.formUnion(intermediateMilestonesReached(
            elapsedSeconds: elapsed,
            targetDurationSeconds: input.targetDurationSeconds
        ))
    }
    var deckCheckpoints = conditionedState.deliveredDeckCheckpoints
    if decision.kind == .deckBehind, let progress = input.deckProgress {
        deckCheckpoints.insert(progress.checkpointID)
    }

    let nextState = CueEngineState(
        fastConditionStartedAt: decision.kind == .tooFast ? nil : fastStart,
        slowConditionStartedAt: decision.kind == .tooSlow ? nil : slowStart,
        fastConditionArmed: decision.kind == .tooFast ? false : fastArmed,
        slowConditionArmed: decision.kind == .tooSlow ? false : slowArmed,
        lastPaceEvaluationAt: lastPaceEvaluationAt,
        lastGlobalCueAt: elapsed,
        lastCueAtByKind: lastByKind,
        deliveredMilestones: milestones,
        deliveredDeckCheckpoints: deckCheckpoints
    )
    return CueEvaluationResult(state: nextState, decision: decision)
}

public func suspendPaceCuePersistence(state: CueEngineState) -> CueEngineState {
    CueEngineState(
        fastConditionStartedAt: nil,
        slowConditionStartedAt: nil,
        fastConditionArmed: state.fastConditionArmed,
        slowConditionArmed: state.slowConditionArmed,
        lastPaceEvaluationAt: nil,
        lastGlobalCueAt: state.lastGlobalCueAt,
        lastCueAtByKind: state.lastCueAtByKind,
        deliveredMilestones: state.deliveredMilestones,
        deliveredDeckCheckpoints: state.deliveredDeckCheckpoints
    )
}

private func isTimeMilestone(_ kind: CueKind) -> Bool {
    kind == .time50 || kind == .time75 || kind == .time90 || kind == .time100
}

private func isScheduledTransition(decision: CueDecision, input: CueEvaluationInput) -> Bool {
    decision.kind == .deckBehind && input.deckProgress?.policy == .scheduledTransition
}

private func orderedCandidates(
    input: CueEvaluationInput,
    state: CueEngineState,
    configuration: CueEngineConfiguration,
    paceEvaluationIsDue: Bool
) -> [CueDecision] {
    let elapsed = input.metrics.elapsedSeconds
    var decisions: [CueDecision] = []

    if !state.deliveredMilestones.contains(.time100), elapsed >= input.targetDurationSeconds {
        decisions.append(CueDecision(kind: .time100, reason: "Reached 100% of target time"))
    }

    if let deck = input.deckProgress,
       deck.policy == .scheduledTransition,
       elapsed >= deck.targetCumulativeSeconds,
       !state.deliveredDeckCheckpoints.contains(deck.checkpointID) {
        decisions.append(CueDecision(kind: .deckBehind, reason: "Time to move to the next slide"))
    }

    let milestones: [(CueKind, Double)] = [
        (.time90, 0.90),
        (.time75, 0.75),
        (.time50, 0.50),
    ]
    for (kind, fraction) in milestones where !state.deliveredMilestones.contains(kind) {
        if elapsed >= input.targetDurationSeconds * fraction {
            decisions.append(CueDecision(kind: kind, reason: "Reached \(Int(fraction * 100))% of target time"))
        }
    }

    if let deck = input.deckProgress,
       deck.policy == .semanticAlignment,
       !deck.reached,
       deck.confidence >= configuration.deckMinimumConfidence,
       elapsed >= deck.targetCumulativeSeconds + configuration.deckGraceSeconds,
       !state.deliveredDeckCheckpoints.contains(deck.checkpointID) {
        decisions.append(CueDecision(kind: .deckBehind, reason: "Presentation content is behind its checkpoint"))
    }

    let scheduledTransitionIsImminent = input.deckProgress.map { deck in
        deck.policy == .scheduledTransition
            && elapsed >= deck.targetCumulativeSeconds - 2
    } ?? false

    let clusterConfiguration = input.profile.fillerClusterConfiguration
    let recentFillers = input.recentFillerOffsets.filter {
        $0 > elapsed - TimeInterval(clusterConfiguration.windowSeconds) && $0 <= elapsed
    }
    if !scheduledTransitionIsImminent,
       recentFillers.count >= clusterConfiguration.requiredFillerCount {
        decisions.append(
            CueDecision(
                kind: .fillerBurst,
                reason: "Multiple filler words in the last \(clusterConfiguration.windowSeconds) seconds"
            )
        )
    }

    let enoughSpeech = paceEvidenceIsUsable(input: input, configuration: configuration)
    if !scheduledTransitionIsImminent,
       paceEvaluationIsDue,
       enoughSpeech,
       let fastStart = state.fastConditionStartedAt,
       elapsed - fastStart >= configuration.fastPersistenceSeconds {
        decisions.append(CueDecision(kind: .tooFast, reason: "Speaking above target pace"))
    }
    if !scheduledTransitionIsImminent,
       paceEvaluationIsDue,
       enoughSpeech,
       let slowStart = state.slowConditionStartedAt,
       elapsed - slowStart >= configuration.slowPersistenceSeconds {
        decisions.append(CueDecision(kind: .tooSlow, reason: "Speaking below target pace"))
    }
    return decisions
}

private func paceEvidenceIsUsable(
    input: CueEvaluationInput,
    configuration: CueEngineConfiguration
) -> Bool {
    guard input.metrics.voicedSeconds >= configuration.minimumVoicedSeconds,
          input.paceEvidence.recognizedWordCount >= configuration.minimumRecognizedWords,
          let latestTranscriptEndSeconds = input.paceEvidence.latestTranscriptEndSeconds,
          latestTranscriptEndSeconds.isFinite else {
        return false
    }
    let evidenceAge = input.metrics.elapsedSeconds - latestTranscriptEndSeconds
    return evidenceAge >= -1 && evidenceAge <= configuration.paceTranscriptFreshnessSeconds
}

private func globalCooldownPassed(elapsed: TimeInterval, state: CueEngineState, seconds: TimeInterval) -> Bool {
    guard let last = state.lastGlobalCueAt else { return true }
    return elapsed - last >= seconds
}

private func ruleCooldownPassed(
    kind: CueKind,
    elapsed: TimeInterval,
    state: CueEngineState,
    deckPolicy: DeckCuePolicy?,
    configuration: CueEngineConfiguration
) -> Bool {
    guard let last = state.lastCueAtByKind[kind] else { return true }
    if kind == .deckBehind {
        if deckPolicy == .scheduledTransition { return true }
        return elapsed - last >= configuration.deckCooldownSeconds
    }
    return elapsed - last >= configuration.perRuleCooldownSeconds
}

private func intermediateMilestonesReached(
    elapsedSeconds: TimeInterval,
    targetDurationSeconds: TimeInterval
) -> Set<CueKind> {
    guard targetDurationSeconds > 0 else { return [] }
    let fraction = elapsedSeconds / targetDurationSeconds
    var milestones = Set<CueKind>()
    if fraction >= 0.5 { milestones.insert(.time50) }
    if fraction >= 0.75 { milestones.insert(.time75) }
    if fraction >= 0.9 { milestones.insert(.time90) }
    return milestones
}
