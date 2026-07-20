import Foundation
import SwiftData
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
        paceStandardDeviationWPM: 12.5,
        pauseCount: 5,
        averagePauseSeconds: 0.84,
        longestPauseSeconds: 1.6,
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

@MainActor
@Test("Deleting one session removes its transcript and every related artifact")
func deletingSessionRemovesEveryRelatedArtifact() throws {
    let store = try VoxaDataStore(inMemory: true)
    let sessionID = try #require(UUID(uuidString: "D9C79EC1-9282-4ED8-A43A-89517E136E79"))
    let summary = SessionSummary(
        sessionID: sessionID,
        name: "Private rehearsal",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 90,
        targetDurationSeconds: 120,
        targetMinimumWPM: 130,
        targetMaximumWPM: 160,
        speakingSeconds: 72,
        averageWPM: 144,
        timeInPaceRange: 0.75,
        fillerCount: 2,
        fillersPerSpeakingMinute: 1.67,
        talkRatio: 0.8,
        paceStandardDeviationWPM: 8,
        pauseCount: 3,
        averagePauseSeconds: 0.7,
        longestPauseSeconds: 1.3,
        pitchRangeSemitones: 6,
        energyRangeDB: 10,
        cueCount: 1,
        transcript: "This transcript must be deleted with its session."
    )
    let segment = FinalTranscriptSegment(
        id: try #require(UUID(uuidString: "959839D4-B1FD-4641-91BC-056D995310CA")),
        startSeconds: 0,
        endSeconds: 5,
        text: "This transcript must be deleted."
    )
    let sample = LiveMetrics(
        elapsedSeconds: 5,
        rollingWPM: 144,
        finalizedWordCount: 12,
        fillerCount: 1,
        voicedSeconds: 4,
        talkRatio: 0.8,
        energyDBFS: -20,
        pitchHertz: 180
    )
    let cueEvent = SessionCueEvent(
        sequence: 7,
        kind: .fillerBurst,
        elapsedSeconds: 5,
        reason: "Filler cluster detected.",
        deliveryStatus: .completed
    )
    let checkpoint = SessionCheckpointResult(
        id: "opening",
        label: "Opening",
        targetCumulativeSeconds: 30,
        observedCumulativeSeconds: 28,
        confidence: 0.9,
        status: .reached
    )
    let insight = CoachingInsight(
        schemaVersion: 1,
        overallSummary: "Private coaching summary.",
        strengths: [],
        priorities: [],
        drills: [],
        confidenceNote: "Based on this session."
    )

    try store.saveSession(
        summary: summary,
        segments: [segment],
        samples: [sample],
        cueEvents: [cueEvent],
        checkpointResults: [checkpoint]
    )
    try store.saveInsight(sessionID: sessionID, insight: insight)

    try store.deleteSession(sessionID: sessionID)

    #expect(try store.fetchSessions().isEmpty)
    #expect(try store.fetchInsight(sessionID: sessionID) == nil)
    #expect(try store.context.fetch(FetchDescriptor<TranscriptSegmentRecord>()).isEmpty)
    #expect(try store.context.fetch(FetchDescriptor<MetricSampleRecord>()).isEmpty)
    #expect(try store.context.fetch(FetchDescriptor<CueEventRecord>()).isEmpty)
    #expect(try store.context.fetch(FetchDescriptor<CheckpointResultRecord>()).isEmpty)
}
