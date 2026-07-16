import Foundation
import Testing
import VoxaCore
@testable import VoxaRuntime

@MainActor
@Test("Session persistence round-trips insight evidence")
func sessionPersistenceRoundTripsInsightEvidence() throws {
    let store = try VoxaDataStore(inMemory: true)
    let sessionID = UUID(uuidString: "8CD4BBFB-880B-4F67-B73E-E3A32C57099D")!
    let summary = SessionSummary(
        sessionID: sessionID,
        name: "Pitch rehearsal",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 180,
        targetDurationSeconds: 180,
        targetMinimumWPM: 130,
        targetMaximumWPM: 160,
        speakingSeconds: 140,
        averageWPM: 146,
        timeInPaceRange: 0.81,
        fillerCount: 3,
        fillersPerSpeakingMinute: 1.29,
        talkRatio: 0.78,
        pitchRangeSemitones: 7.1,
        energyRangeDB: 12.4,
        cueCount: 1,
        transcript: "Voxa Cue delivers private feedback while a presenter speaks."
    )
    let cueEvent = SessionCueEvent(
        sequence: 42,
        kind: .tooFast,
        elapsedSeconds: 64,
        reason: "Pace remained above target.",
        deliveryStatus: .completed
    )
    let checkpoint = SessionCheckpointResult(
        id: "solution",
        label: "Solution",
        targetCumulativeSeconds: 90,
        observedCumulativeSeconds: 87,
        confidence: 0.84,
        status: .reached
    )

    try store.saveSession(
        summary: summary,
        segments: [],
        samples: [],
        cueEvents: [cueEvent],
        checkpointResults: [checkpoint]
    )

    #expect(try store.fetchSessions() == [summary])
    let context = try store.fetchInsightContext(sessionID: sessionID)
    #expect(context.cueEvents == [cueEvent])
    #expect(context.checkpoints == [checkpoint])
}
