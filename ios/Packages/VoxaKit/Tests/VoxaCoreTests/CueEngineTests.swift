import Foundation
import Testing
@testable import VoxaCore

private let profile = CoachingProfile.rehearsalV1()
private let configuration = CueEngineConfiguration.version1()

@Test("The MVP profile excludes the deferred deck cue")
func mvpProfileContainsOnlyPhoneFirstCues() {
    #expect(CueKind.liveMVP == [.tooFast, .tooSlow, .fillerBurst, .time75, .time90, .time100])
    #expect(profile.enabledCues == Set(CueKind.liveMVP))
    #expect(profile.intensityByCue.keys.allSatisfy { CueKind.liveMVP.contains($0) })
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
        fillers: [90, 95],
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
        fillers: [22, 24],
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

@Test("Short presentations receive every time milestone on schedule")
func shortPresentationMilestonesBypassGeneralCooldown() {
    let at75 = evaluateCue(
        input: makeInput(elapsed: 45, wpm: 145, words: 100, voiced: 35, fillers: [], target: 60, deck: nil),
        state: .initial(),
        configuration: configuration
    )
    let at90 = evaluateCue(
        input: makeInput(elapsed: 54, wpm: 145, words: 120, voiced: 42, fillers: [], target: 60, deck: nil),
        state: at75.state,
        configuration: configuration
    )
    let at100 = evaluateCue(
        input: makeInput(elapsed: 60, wpm: 145, words: 135, voiced: 47, fillers: [], target: 60, deck: nil),
        state: at90.state,
        configuration: configuration
    )

    #expect(at75.decision?.kind == .time75)
    #expect(at90.decision?.kind == .time90)
    #expect(at100.decision?.kind == .time100)
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
