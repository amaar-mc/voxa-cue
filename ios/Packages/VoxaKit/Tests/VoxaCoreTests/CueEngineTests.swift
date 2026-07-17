import Foundation
import Testing
@testable import VoxaCore

private let profile = CoachingProfile.rehearsalV1()
private let configuration = CueEngineConfiguration.version1()

@Test("The default profile enables only essential cues with distinct signals")
func mvpProfileContainsOnlyPhoneFirstCues() {
    #expect(CueKind.liveMVP == [.tooFast, .fillerBurst, .time50, .time100, .tooSlow, .time75, .time90])
    #expect(profile.enabledCues == Set(CueKind.essentialDefaults))
    #expect(profile.intensityByCue.keys.allSatisfy { CueKind.liveMVP.contains($0) })
    #expect(profile.patternByCue[.tooFast] == .doubleTap)
    #expect(profile.patternByCue[.fillerBurst] == .calmWave)
    #expect(profile.patternByCue[.time50] == .tripleTap)
    #expect(profile.patternByCue[.time100] == .deadlineHold)
    #expect(profile.intensityByCue[.time100] == .strong)
    #expect(!profile.enabledCues.contains(.deckBehind))
}

@Test("Time milestone outranks filler and pace candidates")
func timeMilestoneHasPriority() {
    let initial = CueEngineState(
        fastConditionStartedAt: 0,
        slowConditionStartedAt: nil,
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
        deck: nil
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
        deck: nil
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
        deck: nil
    )
    let second = evaluateCue(input: secondInput, state: first.state, configuration: configuration)
    #expect(second.decision?.kind == .tooFast)
}

@Test("Global cooldown suppresses overlapping cues")
func globalCooldownSuppressesCue() {
    let state = CueEngineState(
        fastConditionStartedAt: 0,
        slowConditionStartedAt: nil,
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
        deck: nil
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
        deck: deck
    )

    let result = evaluateCue(input: input, state: .initial(), configuration: configuration)
    #expect(result.decision == nil)
}

@Test("Short presentations receive enabled time milestones on schedule")
func shortPresentationMilestonesBypassGeneralCooldown() {
    let at50 = evaluateCue(
        input: makeInput(elapsed: 30, wpm: 145, words: 65, voiced: 24, fillers: [], target: 60, deck: nil),
        state: .initial(),
        configuration: configuration
    )
    let at100 = evaluateCue(
        input: makeInput(elapsed: 60, wpm: 145, words: 135, voiced: 47, fillers: [], target: 60, deck: nil),
        state: at50.state,
        configuration: configuration
    )

    #expect(at50.decision?.kind == .time50)
    #expect(at100.decision?.kind == .time100)
}

@Test("Crossing the target marks every earlier milestone delivered")
func targetMilestoneSupersedesEarlierMilestones() {
    let result = evaluateCue(
        input: makeInput(elapsed: 60, wpm: 145, words: 135, voiced: 47, fillers: [], target: 60, deck: nil),
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
    deck: DeckProgress?
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
        targetDurationSeconds: target,
        recentFillerOffsets: fillers,
        deckProgress: deck,
        profile: profile,
        isPaused: false
    )
}
