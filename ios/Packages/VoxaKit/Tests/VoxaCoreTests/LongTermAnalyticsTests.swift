import Foundation
import Testing
@testable import VoxaCore

@Test("Long-term analytics weight rate metrics by their measured exposure")
func longTermAnalyticsWeightsRatesByExposure() throws {
    let first = analyticsSession(
        id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000301")),
        startedAt: Date(timeIntervalSince1970: 100),
        durationSeconds: 60,
        targetDurationSeconds: 60,
        speakingSeconds: 30,
        averageWPM: 100,
        timeInPaceRange: 0.50,
        fillerCount: 3,
        paceStandardDeviationWPM: 10,
        pauseCount: 2,
        averagePauseSeconds: 1,
        longestPauseSeconds: 1.5,
        pitchRangeSemitones: 4,
        energyRangeDB: 8
    )
    let second = analyticsSession(
        id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000302")),
        startedAt: Date(timeIntervalSince1970: 200),
        durationSeconds: 180,
        targetDurationSeconds: 160,
        speakingSeconds: 150,
        averageWPM: 160,
        timeInPaceRange: 0.90,
        fillerCount: 2,
        paceStandardDeviationWPM: 20,
        pauseCount: 3,
        averagePauseSeconds: 2,
        longestPauseSeconds: 3,
        pitchRangeSemitones: 8,
        energyRangeDB: 12
    )

    let result = makeLongTermAnalytics(sessions: [first, second])

    #expect(result.sessionCount == 2)
    #expect(abs(result.averageWPM - 145) < 0.001)
    #expect(abs(result.timeInPaceRange - 0.80) < 0.001)
    #expect(abs(result.fillersPerSpeakingMinute - (5.0 / 3.0)) < 0.001)
    #expect(abs(result.talkRatio - 0.75) < 0.001)
    let paceDeviation = try #require(result.averagePaceStandardDeviationWPM)
    #expect(abs(paceDeviation - 17.5) < 0.001)
    #expect(result.measuredIntonationSessionCount == 2)
    #expect(result.averagePitchRangeSemitones == 6)
    #expect(result.averageEnergyRangeDB == 10)
    #expect(result.measuredPauseSessionCount == 2)
    let pauseRate = try #require(result.pausesPerPresentationMinute)
    let pauseLength = try #require(result.averagePauseSeconds)
    #expect(abs(pauseRate - 1.25) < 0.001)
    #expect(abs(pauseLength - 1.6) < 0.001)
    #expect(result.longestPauseSeconds == 3)
    #expect(result.onTargetSessionRatio == 0.5)
    #expect(result.averageAbsoluteTimingDeviationSeconds == 10)
}

@Test("Long-term analytics do not turn unavailable measurements into zeroes")
func longTermAnalyticsPreservesUnavailableMeasurements() throws {
    let session = analyticsSession(
        id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000303")),
        startedAt: Date(timeIntervalSince1970: 300),
        durationSeconds: 120,
        targetDurationSeconds: 120,
        speakingSeconds: 90,
        averageWPM: 145,
        timeInPaceRange: 0.80,
        fillerCount: 1,
        paceStandardDeviationWPM: nil,
        pauseCount: nil,
        averagePauseSeconds: nil,
        longestPauseSeconds: nil,
        pitchRangeSemitones: nil,
        energyRangeDB: nil
    )

    let result = makeLongTermAnalytics(sessions: [session])

    #expect(result.averagePaceStandardDeviationWPM == nil)
    #expect(result.measuredIntonationSessionCount == 0)
    #expect(result.averagePitchRangeSemitones == nil)
    #expect(result.averageEnergyRangeDB == nil)
    #expect(result.measuredPauseSessionCount == 0)
    #expect(result.pausesPerPresentationMinute == nil)
    #expect(result.averagePauseSeconds == nil)
    #expect(result.longestPauseSeconds == nil)
}

private func analyticsSession(
    id: UUID,
    startedAt: Date,
    durationSeconds: TimeInterval,
    targetDurationSeconds: TimeInterval,
    speakingSeconds: TimeInterval,
    averageWPM: Double,
    timeInPaceRange: Double,
    fillerCount: Int,
    paceStandardDeviationWPM: Double?,
    pauseCount: Int?,
    averagePauseSeconds: Double?,
    longestPauseSeconds: Double?,
    pitchRangeSemitones: Double?,
    energyRangeDB: Double?
) -> SessionSummary {
    SessionSummary(
        sessionID: id,
        name: "Analytics rehearsal",
        startedAt: startedAt,
        durationSeconds: durationSeconds,
        targetDurationSeconds: targetDurationSeconds,
        targetMinimumWPM: 130,
        targetMaximumWPM: 160,
        speakingSeconds: speakingSeconds,
        averageWPM: averageWPM,
        timeInPaceRange: timeInPaceRange,
        fillerCount: fillerCount,
        fillersPerSpeakingMinute: speakingSeconds > 0 ? Double(fillerCount) * 60 / speakingSeconds : 0,
        talkRatio: durationSeconds > 0 ? speakingSeconds / durationSeconds : 0,
        paceStandardDeviationWPM: paceStandardDeviationWPM,
        pauseCount: pauseCount,
        averagePauseSeconds: averagePauseSeconds,
        longestPauseSeconds: longestPauseSeconds,
        pitchRangeSemitones: pitchRangeSemitones,
        energyRangeDB: energyRangeDB,
        cueCount: 0,
        transcript: "Measured transcript"
    )
}
