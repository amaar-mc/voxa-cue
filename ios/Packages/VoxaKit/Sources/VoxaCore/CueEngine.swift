import Foundation

public struct CueEngineConfiguration: Equatable, Sendable {
    public let paceWindowSeconds: TimeInterval
    public let minimumVoicedSeconds: TimeInterval
    public let minimumFinalizedWords: Int
    public let fastPersistenceSeconds: TimeInterval
    public let slowPersistenceSeconds: TimeInterval
    public let fillerWindowSeconds: TimeInterval
    public let fillerBurstCount: Int
    public let perRuleCooldownSeconds: TimeInterval
    public let deckCooldownSeconds: TimeInterval
    public let globalCooldownSeconds: TimeInterval
    public let deckGraceSeconds: TimeInterval
    public let deckMinimumConfidence: Double

    public init(
        paceWindowSeconds: TimeInterval,
        minimumVoicedSeconds: TimeInterval,
        minimumFinalizedWords: Int,
        fastPersistenceSeconds: TimeInterval,
        slowPersistenceSeconds: TimeInterval,
        fillerWindowSeconds: TimeInterval,
        fillerBurstCount: Int,
        perRuleCooldownSeconds: TimeInterval,
        deckCooldownSeconds: TimeInterval,
        globalCooldownSeconds: TimeInterval,
        deckGraceSeconds: TimeInterval,
        deckMinimumConfidence: Double
    ) {
        self.paceWindowSeconds = paceWindowSeconds
        self.minimumVoicedSeconds = minimumVoicedSeconds
        self.minimumFinalizedWords = minimumFinalizedWords
        self.fastPersistenceSeconds = fastPersistenceSeconds
        self.slowPersistenceSeconds = slowPersistenceSeconds
        self.fillerWindowSeconds = fillerWindowSeconds
        self.fillerBurstCount = fillerBurstCount
        self.perRuleCooldownSeconds = perRuleCooldownSeconds
        self.deckCooldownSeconds = deckCooldownSeconds
        self.globalCooldownSeconds = globalCooldownSeconds
        self.deckGraceSeconds = deckGraceSeconds
        self.deckMinimumConfidence = deckMinimumConfidence
    }

    public static func version1() -> CueEngineConfiguration {
        CueEngineConfiguration(
            paceWindowSeconds: 20,
            minimumVoicedSeconds: 8,
            minimumFinalizedWords: 20,
            fastPersistenceSeconds: 4,
            slowPersistenceSeconds: 5,
            fillerWindowSeconds: 20,
            fillerBurstCount: 2,
            perRuleCooldownSeconds: 30,
            deckCooldownSeconds: 45,
            globalCooldownSeconds: 12,
            deckGraceSeconds: 15,
            deckMinimumConfidence: 0.70
        )
    }
}

public struct DeckProgress: Equatable, Sendable {
    public let checkpointID: String
    public let targetCumulativeSeconds: TimeInterval
    public let reached: Bool
    public let confidence: Double

    public init(checkpointID: String, targetCumulativeSeconds: TimeInterval, reached: Bool, confidence: Double) {
        self.checkpointID = checkpointID
        self.targetCumulativeSeconds = targetCumulativeSeconds
        self.reached = reached
        self.confidence = confidence
    }
}

public struct CueEvaluationInput: Equatable, Sendable {
    public let metrics: LiveMetrics
    public let targetDurationSeconds: TimeInterval
    public let recentFillerOffsets: [TimeInterval]
    public let deckProgress: DeckProgress?
    public let profile: CoachingProfile
    public let isPaused: Bool

    public init(
        metrics: LiveMetrics,
        targetDurationSeconds: TimeInterval,
        recentFillerOffsets: [TimeInterval],
        deckProgress: DeckProgress?,
        profile: CoachingProfile,
        isPaused: Bool
    ) {
        self.metrics = metrics
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
    public let lastGlobalCueAt: TimeInterval?
    public let lastCueAtByKind: [CueKind: TimeInterval]
    public let deliveredMilestones: Set<CueKind>
    public let deliveredDeckCheckpoints: Set<String>

    public init(
        fastConditionStartedAt: TimeInterval?,
        slowConditionStartedAt: TimeInterval?,
        lastGlobalCueAt: TimeInterval?,
        lastCueAtByKind: [CueKind: TimeInterval],
        deliveredMilestones: Set<CueKind>,
        deliveredDeckCheckpoints: Set<String>
    ) {
        self.fastConditionStartedAt = fastConditionStartedAt
        self.slowConditionStartedAt = slowConditionStartedAt
        self.lastGlobalCueAt = lastGlobalCueAt
        self.lastCueAtByKind = lastCueAtByKind
        self.deliveredMilestones = deliveredMilestones
        self.deliveredDeckCheckpoints = deliveredDeckCheckpoints
    }

    public static func initial() -> CueEngineState {
        CueEngineState(
            fastConditionStartedAt: nil,
            slowConditionStartedAt: nil,
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
    guard !input.isPaused else { return CueEvaluationResult(state: state, decision: nil) }

    let fastStart = input.metrics.rollingWPM > input.profile.maximumWPM
        ? (state.fastConditionStartedAt ?? elapsed)
        : nil
    let slowStart = input.metrics.rollingWPM > 0 && input.metrics.rollingWPM < input.profile.minimumWPM
        ? (state.slowConditionStartedAt ?? elapsed)
        : nil
    let conditionedState = CueEngineState(
        fastConditionStartedAt: fastStart,
        slowConditionStartedAt: slowStart,
        lastGlobalCueAt: state.lastGlobalCueAt,
        lastCueAtByKind: state.lastCueAtByKind,
        deliveredMilestones: state.deliveredMilestones,
        deliveredDeckCheckpoints: state.deliveredDeckCheckpoints
    )

    let candidates = orderedCandidates(input: input, state: conditionedState, configuration: configuration)
    guard let decision = candidates.first(where: { candidate in
        input.profile.enabledCues.contains(candidate.kind)
            && ruleCooldownPassed(
                kind: candidate.kind,
                elapsed: elapsed,
                state: conditionedState,
                configuration: configuration
            )
    }) else {
        return CueEvaluationResult(state: conditionedState, decision: nil)
    }
    guard isTimeMilestone(decision.kind)
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
    case .time75:
        milestones.insert(decision.kind)
    case .time90:
        milestones.formUnion([.time75, .time90])
    case .time100:
        milestones.formUnion([.time75, .time90, .time100])
    case .tooFast, .tooSlow, .fillerBurst, .deckBehind:
        break
    }
    var deckCheckpoints = conditionedState.deliveredDeckCheckpoints
    if decision.kind == .deckBehind, let progress = input.deckProgress {
        deckCheckpoints.insert(progress.checkpointID)
    }

    let nextState = CueEngineState(
        fastConditionStartedAt: decision.kind == .tooFast ? nil : fastStart,
        slowConditionStartedAt: decision.kind == .tooSlow ? nil : slowStart,
        lastGlobalCueAt: elapsed,
        lastCueAtByKind: lastByKind,
        deliveredMilestones: milestones,
        deliveredDeckCheckpoints: deckCheckpoints
    )
    return CueEvaluationResult(state: nextState, decision: decision)
}

private func isTimeMilestone(_ kind: CueKind) -> Bool {
    kind == .time75 || kind == .time90 || kind == .time100
}

private func orderedCandidates(
    input: CueEvaluationInput,
    state: CueEngineState,
    configuration: CueEngineConfiguration
) -> [CueDecision] {
    let elapsed = input.metrics.elapsedSeconds
    var decisions: [CueDecision] = []

    let milestones: [(CueKind, Double)] = [(.time100, 1.0), (.time90, 0.90), (.time75, 0.75)]
    for (kind, fraction) in milestones where !state.deliveredMilestones.contains(kind) {
        if elapsed >= input.targetDurationSeconds * fraction {
            decisions.append(CueDecision(kind: kind, reason: "Reached \(Int(fraction * 100))% of target time"))
        }
    }

    if let deck = input.deckProgress,
       !deck.reached,
       deck.confidence >= configuration.deckMinimumConfidence,
       elapsed >= deck.targetCumulativeSeconds + configuration.deckGraceSeconds,
       !state.deliveredDeckCheckpoints.contains(deck.checkpointID) {
        decisions.append(CueDecision(kind: .deckBehind, reason: "Presentation content is behind its checkpoint"))
    }

    let recentFillers = input.recentFillerOffsets.filter {
        $0 > elapsed - configuration.fillerWindowSeconds && $0 <= elapsed
    }
    if recentFillers.count >= configuration.fillerBurstCount {
        decisions.append(CueDecision(kind: .fillerBurst, reason: "Multiple filler words in the last 20 seconds"))
    }

    let enoughSpeech = input.metrics.voicedSeconds >= configuration.minimumVoicedSeconds
        && input.metrics.finalizedWordCount >= configuration.minimumFinalizedWords
    if enoughSpeech,
       let fastStart = state.fastConditionStartedAt,
       elapsed - fastStart >= configuration.fastPersistenceSeconds {
        decisions.append(CueDecision(kind: .tooFast, reason: "Speaking above target pace"))
    }
    if enoughSpeech,
       let slowStart = state.slowConditionStartedAt,
       elapsed - slowStart >= configuration.slowPersistenceSeconds {
        decisions.append(CueDecision(kind: .tooSlow, reason: "Speaking below target pace"))
    }
    return decisions
}

private func globalCooldownPassed(elapsed: TimeInterval, state: CueEngineState, seconds: TimeInterval) -> Bool {
    guard let last = state.lastGlobalCueAt else { return true }
    return elapsed - last >= seconds
}

private func ruleCooldownPassed(
    kind: CueKind,
    elapsed: TimeInterval,
    state: CueEngineState,
    configuration: CueEngineConfiguration
) -> Bool {
    guard let last = state.lastCueAtByKind[kind] else { return true }
    let cooldown = kind == .deckBehind ? configuration.deckCooldownSeconds : configuration.perRuleCooldownSeconds
    return elapsed - last >= cooldown
}
