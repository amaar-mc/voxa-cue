import Foundation
import Testing
@testable import VoxaCore

@Test("A session at ninety percent of its target is on target")
func timingOutcomeIncludesLowerToleranceBoundary() {
    let outcome = TimingOutcome(
        durationSeconds: 270,
        targetDurationSeconds: 300
    )

    #expect(outcome == .onTarget)
}

@Test("A session below ninety percent of its target is partial")
func timingOutcomeClassifiesMateriallyIncompleteSession() {
    let outcome = TimingOutcome(
        durationSeconds: 269.9,
        targetDurationSeconds: 300
    )

    #expect(outcome == .partial)
}

@Test("A session above one hundred five percent of its target is over target")
func timingOutcomeClassifiesOverTargetSession() {
    let outcome = TimingOutcome(
        durationSeconds: 315.1,
        targetDurationSeconds: 300
    )

    #expect(outcome == .overTarget)
}

@Test("A session at one hundred five percent of its target remains on target")
func timingOutcomeIncludesUpperToleranceBoundary() {
    let outcome = TimingOutcome(
        durationSeconds: 315,
        targetDurationSeconds: 300
    )

    #expect(outcome == .onTarget)
}

@Test("A nonpositive target duration fails closed as partial")
func timingOutcomeRejectsNonpositiveTarget() {
    let outcome = TimingOutcome(
        durationSeconds: 0,
        targetDurationSeconds: 0
    )

    #expect(outcome == .partial)
}

@Test("Non-finite timing data fails closed as partial")
func timingOutcomeRejectsNonfiniteTiming() {
    let outcome = TimingOutcome(
        durationSeconds: .nan,
        targetDurationSeconds: 300
    )

    #expect(outcome == .partial)
}

@Test("A session summary exposes the shared timing outcome")
func sessionSummaryUsesSharedTimingOutcome() {
    let summary = SessionSummary(
        sessionID: UUID(),
        name: "Pitch rehearsal",
        startedAt: Date(timeIntervalSince1970: 0),
        durationSeconds: 270,
        targetDurationSeconds: 300,
        targetMinimumWPM: 130,
        targetMaximumWPM: 160,
        speakingSeconds: 240,
        averageWPM: 145,
        timeInPaceRange: 0.8,
        fillerCount: 2,
        fillersPerSpeakingMinute: 0.5,
        talkRatio: 0.8,
        pitchRangeSemitones: nil,
        energyRangeDB: nil,
        cueCount: 1,
        transcript: "Pitch rehearsal"
    )

    #expect(summary.timingOutcome == .onTarget)
}
