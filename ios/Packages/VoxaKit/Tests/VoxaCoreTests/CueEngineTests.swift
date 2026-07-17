import Foundation
import Testing
@testable import VoxaCore

private let profile = CoachingProfile.rehearsalV1()
private let configuration = CueEngineConfiguration.version1()

@Test("The default profile enables only essential cues with distinct signals")
func mvpProfileContainsOnlyPhoneFirstCues() {
    #expect(FillerClusterConfiguration.requiredCountRange == 1...6)
    #expect(CueKind.liveMVP == [.tooFast, .fillerBurst, .time50, .time100, .tooSlow, .time75, .time90])
    #expect(profile.enabledCues == Set(CueKind.essentialDefaults))
    #expect(profile.intensityByCue.keys.allSatisfy { CueKind.liveMVP.contains($0) })
    #expect(profile.patternByCue[.tooFast] == .doubleTap)
    #expect(profile.patternByCue[.fillerBurst] == .calmWave)
    #expect(profile.patternByCue[.time50] == .tripleTap)
    #expect(profile.patternByCue[.time100] == .deadlineHold)
    #expect(profile.intensityByCue[.time100] == .strong)
    #expect(profile.fillerClusterConfiguration == .responsiveDefault())
    #expect(!profile.enabledCues.contains(.deckBehind))
}

@Test("Filler count and lookback window control clusters without changing the cooldown")
func fillerClusterConfigurationControlsThreshold() {
    let configurations = [
        FillerClusterConfiguration(requiredFillerCount: 1, windowSeconds: 5),
        FillerClusterConfiguration(requiredFillerCount: 2, windowSeconds: 5),
        FillerClusterConfiguration(requiredFillerCount: 3, windowSeconds: 10),
        FillerClusterConfiguration(requiredFillerCount: 5, windowSeconds: 20),
    ]

    for clusterConfiguration in configurations {
        let requiredCount = clusterConfiguration.requiredFillerCount
        let belowThreshold = evaluateCue(
            input: makeFillerInput(
                clusterConfiguration: clusterConfiguration,
                elapsed: 30,
                fillerOffsets: Array(0..<(requiredCount - 1)).map { 30 - Double($0) }
            ),
            state: .initial(),
            configuration: configuration
        )
        let atThreshold = evaluateCue(
            input: makeFillerInput(
                clusterConfiguration: clusterConfiguration,
                elapsed: 30,
                fillerOffsets: Array(0..<requiredCount).map { 30 - Double($0) }
            ),
            state: .initial(),
            configuration: configuration
        )

        #expect(belowThreshold.decision == nil)
        #expect(atThreshold.decision?.kind == .fillerBurst)
    }

    let responsive = FillerClusterConfiguration.responsiveDefault()
    let firstCue = evaluateCue(
        input: makeFillerInput(clusterConfiguration: responsive, elapsed: 30, fillerOffsets: [28, 29]),
        state: .initial(),
        configuration: configuration
    )
    let duringCooldown = evaluateCue(
        input: makeFillerInput(clusterConfiguration: responsive, elapsed: 40, fillerOffsets: [39, 40]),
        state: firstCue.state,
        configuration: configuration
    )

    #expect(firstCue.decision?.kind == .fillerBurst)
    #expect(duringCooldown.decision == nil)

    let exactWindowBoundary = evaluateCue(
        input: makeFillerInput(clusterConfiguration: responsive, elapsed: 30, fillerOffsets: [25, 29]),
        state: .initial(),
        configuration: configuration
    )
    let justInsideWindow = evaluateCue(
        input: makeFillerInput(clusterConfiguration: responsive, elapsed: 30, fillerOffsets: [25.001, 29]),
        state: .initial(),
        configuration: configuration
    )

    #expect(exactWindowBoundary.decision == nil)
    #expect(justInsideWindow.decision?.kind == .fillerBurst)
}

@Test("Time milestone outranks filler and pace candidates")
func timeMilestoneHasPriority() {
    let initial = CueEngineState(
        fastConditionStartedAt: 0,
        slowConditionStartedAt: nil,
        fastConditionArmed: true,
        slowConditionArmed: true,
        lastPaceEvaluationAt: nil,
        lastGlobalCueAt: nil,
        lastCueAtByKind: [:],
        deliveredMilestones: [],
        deliveredDeckCheckpoints: []
    )
    let input = makeInput(
        elapsed: 100,
        wpm: 190,
        words: 100,
        voiced: 80,
        fillers: [89, 93, 97],
        target: 100,
        deck: nil,
        latestTranscriptEnd: 100
    )

    let result = evaluateCue(input: input, state: initial, configuration: configuration)

    #expect(result.decision?.kind == .time100)
}

@Test("Fast pace requires persistence and enough committed speech")
func fastPaceRequiresPersistence() {
    let firstInput = makeInput(
        elapsed: 20,
        wpm: 180,
        words: 30,
        voiced: 12,
        fillers: [],
        target: 600,
        deck: nil,
        latestTranscriptEnd: 20
    )
    let first = evaluateCue(input: firstInput, state: .initial(), configuration: configuration)
    #expect(first.decision == nil)

    let secondInput = makeInput(
        elapsed: 24,
        wpm: 180,
        words: 36,
        voiced: 16,
        fillers: [],
        target: 600,
        deck: nil,
        latestTranscriptEnd: 24
    )
    let second = evaluateCue(input: secondInput, state: first.state, configuration: configuration)
    #expect(second.decision?.kind == .tooFast)
}

@Test("Stale transcript evidence breaks pace persistence")
func staleTranscriptBreaksPacePersistence() {
    let first = evaluateCue(
        input: makeInput(
            elapsed: 20,
            wpm: 180,
            words: 30,
            voiced: 12,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 20
        ),
        state: .initial(),
        configuration: configuration
    )
    let stale = evaluateCue(
        input: makeInput(
            elapsed: 25,
            wpm: 180,
            words: 36,
            voiced: 16,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 20
        ),
        state: first.state,
        configuration: configuration
    )

    #expect(first.decision == nil)
    #expect(stale.decision == nil)
    #expect(stale.state.fastConditionStartedAt == nil)
}

@Test("Pace conditions update only on the tuned three-second cadence")
func paceEvaluationUsesTunedCadence() {
    let started = evaluateCue(
        input: makeInput(
            elapsed: 3,
            wpm: 180,
            words: 6,
            voiced: 3,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 3
        ),
        state: .initial(),
        configuration: configuration
    )
    let transient = evaluateCue(
        input: makeInput(
            elapsed: 4,
            wpm: 145,
            words: 8,
            voiced: 4,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 4
        ),
        state: started.state,
        configuration: configuration
    )
    let nextEvaluation = evaluateCue(
        input: makeInput(
            elapsed: 6,
            wpm: 145,
            words: 12,
            voiced: 6,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 6
        ),
        state: transient.state,
        configuration: configuration
    )

    #expect(started.state.fastConditionStartedAt == 3)
    #expect(transient.state.fastConditionStartedAt == 3)
    #expect(nextEvaluation.state.fastConditionStartedAt == nil)
    #expect(nextEvaluation.decision == nil)
}

@Test("Fast pace rearms only after crossing the hysteresis band")
func fastPaceRequiresHysteresisBeforeRearming() {
    let started = evaluateCue(
        input: makeInput(
            elapsed: 20,
            wpm: 180,
            words: 30,
            voiced: 12,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 20
        ),
        state: .initial(),
        configuration: configuration
    )
    let firstCue = evaluateCue(
        input: makeInput(
            elapsed: 24,
            wpm: 180,
            words: 36,
            voiced: 16,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 24
        ),
        state: started.state,
        configuration: configuration
    )
    let stillFast = evaluateCue(
        input: makeInput(
            elapsed: 60,
            wpm: 180,
            words: 90,
            voiced: 45,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 60
        ),
        state: firstCue.state,
        configuration: configuration
    )
    let rearmed = evaluateCue(
        input: makeInput(
            elapsed: 63,
            wpm: 150,
            words: 92,
            voiced: 46,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 63
        ),
        state: stillFast.state,
        configuration: configuration
    )
    let restarted = evaluateCue(
        input: makeInput(
            elapsed: 66,
            wpm: 180,
            words: 95,
            voiced: 47,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 66
        ),
        state: rearmed.state,
        configuration: configuration
    )
    let secondCue = evaluateCue(
        input: makeInput(
            elapsed: 72,
            wpm: 180,
            words: 107,
            voiced: 51,
            fillers: [],
            target: 600,
            deck: nil,
            latestTranscriptEnd: 72
        ),
        state: restarted.state,
        configuration: configuration
    )

    #expect(firstCue.decision?.kind == .tooFast)
    #expect(stillFast.decision == nil)
    #expect(secondCue.decision?.kind == .tooFast)
}

@Test("Global cooldown suppresses overlapping cues")
func globalCooldownSuppressesCue() {
    let state = CueEngineState(
        fastConditionStartedAt: 0,
        slowConditionStartedAt: nil,
        fastConditionArmed: true,
        slowConditionArmed: true,
        lastPaceEvaluationAt: nil,
        lastGlobalCueAt: 20,
        lastCueAtByKind: [.fillerBurst: 20],
        deliveredMilestones: [],
        deliveredDeckCheckpoints: []
    )
    let input = makeInput(
        elapsed: 25,
        wpm: 180,
        words: 40,
        voiced: 20,
        fillers: [21, 23, 24],
        target: 600,
        deck: nil,
        latestTranscriptEnd: 25
    )

    let result = evaluateCue(input: input, state: state, configuration: configuration)
    #expect(result.decision == nil)
}

@Test("Uncertain deck progress never vibrates")
func uncertainDeckProgressIsSuppressed() {
    let deck = DeckProgress(
        checkpointID: "slide-2",
        targetCumulativeSeconds: 30,
        reached: false,
        confidence: 0.50
    )
    let input = makeInput(
        elapsed: 60,
        wpm: 145,
        words: 80,
        voiced: 40,
        fillers: [],
        target: 600,
        deck: deck,
        latestTranscriptEnd: 60
    )

    let result = evaluateCue(input: input, state: .initial(), configuration: configuration)
    #expect(result.decision == nil)
}

@Test("Short presentations receive enabled time milestones on schedule")
func shortPresentationMilestonesBypassGeneralCooldown() {
    let at50 = evaluateCue(
        input: makeInput(
            elapsed: 30,
            wpm: 145,
            words: 65,
            voiced: 24,
            fillers: [],
            target: 60,
            deck: nil,
            latestTranscriptEnd: 30
        ),
        state: .initial(),
        configuration: configuration
    )
    let at100 = evaluateCue(
        input: makeInput(
            elapsed: 60,
            wpm: 145,
            words: 135,
            voiced: 47,
            fillers: [],
            target: 60,
            deck: nil,
            latestTranscriptEnd: 60
        ),
        state: at50.state,
        configuration: configuration
    )

    #expect(at50.decision?.kind == .time50)
    #expect(at100.decision?.kind == .time100)
}

@Test("Crossing the target marks every earlier milestone delivered")
func targetMilestoneSupersedesEarlierMilestones() {
    let result = evaluateCue(
        input: makeInput(
            elapsed: 60,
            wpm: 145,
            words: 135,
            voiced: 47,
            fillers: [],
            target: 60,
            deck: nil,
            latestTranscriptEnd: 60
        ),
        state: .initial(),
        configuration: configuration
    )

    #expect(result.decision?.kind == .time100)
    #expect(result.state.deliveredMilestones.isSuperset(of: [.time50, .time75, .time90, .time100]))
}

private func makeInput(
    elapsed: TimeInterval,
    wpm: Double,
    words: Int,
    voiced: TimeInterval,
    fillers: [TimeInterval],
    target: TimeInterval,
    deck: DeckProgress?,
    latestTranscriptEnd: TimeInterval
) -> CueEvaluationInput {
    let metrics = LiveMetrics(
        elapsedSeconds: elapsed,
        rollingWPM: wpm,
        finalizedWordCount: words,
        fillerCount: fillers.count,
        voicedSeconds: voiced,
        talkRatio: computedTalkRatio(voicedSeconds: voiced, elapsedSeconds: elapsed),
        energyDBFS: -24,
        pitchHertz: 180
    )
    return CueEvaluationInput(
        metrics: metrics,
        paceEvidence: PaceEvidence(
            recognizedWordCount: words,
            latestTranscriptEndSeconds: latestTranscriptEnd
        ),
        targetDurationSeconds: target,
        recentFillerOffsets: fillers,
        deckProgress: deck,
        profile: profile,
        isPaused: false
    )
}

private func makeFillerInput(
    clusterConfiguration: FillerClusterConfiguration,
    elapsed: TimeInterval,
    fillerOffsets: [TimeInterval]
) -> CueEvaluationInput {
    let baseProfile = CoachingProfile.rehearsalV1()
    let profile = CoachingProfile(
        minimumWPM: baseProfile.minimumWPM,
        maximumWPM: baseProfile.maximumWPM,
        enabledCues: baseProfile.enabledCues,
        patternByCue: baseProfile.patternByCue,
        intensityByCue: baseProfile.intensityByCue,
        fillerClusterConfiguration: clusterConfiguration,
        highConfidenceFillers: baseProfile.highConfidenceFillers,
        optionalFillers: baseProfile.optionalFillers
    )
    let metrics = LiveMetrics(
        elapsedSeconds: elapsed,
        rollingWPM: 0,
        finalizedWordCount: 0,
        fillerCount: fillerOffsets.count,
        voicedSeconds: 0,
        talkRatio: 0,
        energyDBFS: nil,
        pitchHertz: nil
    )
    return CueEvaluationInput(
        metrics: metrics,
        paceEvidence: PaceEvidence(recognizedWordCount: 0, latestTranscriptEndSeconds: nil),
        targetDurationSeconds: 600,
        recentFillerOffsets: fillerOffsets,
        deckProgress: nil,
        profile: profile,
        isPaused: false
    )
}
