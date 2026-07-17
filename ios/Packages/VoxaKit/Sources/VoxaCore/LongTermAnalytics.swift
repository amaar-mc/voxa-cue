import Foundation

public struct LongTermAnalytics: Equatable, Sendable {
    public let sessionCount: Int
    public let totalPresentationSeconds: TimeInterval
    public let averageWPM: Double
    public let timeInPaceRange: Double
    public let fillersPerSpeakingMinute: Double
    public let talkRatio: Double
    public let onTargetSessionRatio: Double
    public let averageAbsoluteTimingDeviationSeconds: Double
    public let averagePaceStandardDeviationWPM: Double?
    public let averagePitchRangeSemitones: Double?
    public let averageEnergyRangeDB: Double?
    public let measuredIntonationSessionCount: Int
    public let pausesPerPresentationMinute: Double?
    public let averagePauseSeconds: Double?
    public let longestPauseSeconds: Double?
    public let measuredPauseSessionCount: Int

    public init(
        sessionCount: Int,
        totalPresentationSeconds: TimeInterval,
        averageWPM: Double,
        timeInPaceRange: Double,
        fillersPerSpeakingMinute: Double,
        talkRatio: Double,
        onTargetSessionRatio: Double,
        averageAbsoluteTimingDeviationSeconds: Double,
        averagePaceStandardDeviationWPM: Double?,
        averagePitchRangeSemitones: Double?,
        averageEnergyRangeDB: Double?,
        measuredIntonationSessionCount: Int,
        pausesPerPresentationMinute: Double?,
        averagePauseSeconds: Double?,
        longestPauseSeconds: Double?,
        measuredPauseSessionCount: Int
    ) {
        self.sessionCount = sessionCount
        self.totalPresentationSeconds = totalPresentationSeconds
        self.averageWPM = averageWPM
        self.timeInPaceRange = timeInPaceRange
        self.fillersPerSpeakingMinute = fillersPerSpeakingMinute
        self.talkRatio = talkRatio
        self.onTargetSessionRatio = onTargetSessionRatio
        self.averageAbsoluteTimingDeviationSeconds = averageAbsoluteTimingDeviationSeconds
        self.averagePaceStandardDeviationWPM = averagePaceStandardDeviationWPM
        self.averagePitchRangeSemitones = averagePitchRangeSemitones
        self.averageEnergyRangeDB = averageEnergyRangeDB
        self.measuredIntonationSessionCount = measuredIntonationSessionCount
        self.pausesPerPresentationMinute = pausesPerPresentationMinute
        self.averagePauseSeconds = averagePauseSeconds
        self.longestPauseSeconds = longestPauseSeconds
        self.measuredPauseSessionCount = measuredPauseSessionCount
    }
}

public func makeLongTermAnalytics(sessions: [SessionSummary]) -> LongTermAnalytics {
    let measuredSessions = sessions.filter { session in
        session.durationSeconds.isFinite && session.durationSeconds > 0
    }
    let totalDuration = measuredSessions.reduce(0) { $0 + $1.durationSeconds }
    let totalSpeaking = measuredSessions.reduce(0) { $0 + max(0, $1.speakingSeconds) }
    let totalFillers = measuredSessions.reduce(0) { $0 + max(0, $1.fillerCount) }
    let onTargetCount = measuredSessions.filter { $0.timingOutcome == .onTarget }.count
    let timingDeviationTotal = measuredSessions.reduce(0.0) { partial, session in
        partial + abs(session.durationSeconds - session.targetDurationSeconds)
    }

    let paceVariabilityMeasurements = measuredSessions.compactMap { session -> WeightedMeasurement? in
        guard let value = session.paceStandardDeviationWPM,
              value.isFinite,
              value >= 0 else { return nil }
        return WeightedMeasurement(value: value, weight: session.durationSeconds)
    }
    let pitchMeasurements = measuredSessions.compactMap { session -> Double? in
        guard let value = session.pitchRangeSemitones, value.isFinite, value >= 0 else { return nil }
        return value
    }
    let energyMeasurements = measuredSessions.compactMap { session -> Double? in
        guard let value = session.energyRangeDB, value.isFinite, value >= 0 else { return nil }
        return value
    }
    let pauseSessions = measuredSessions.filter { $0.pauseCount != nil }
    let totalPauseCount = pauseSessions.reduce(0) { $0 + max(0, $1.pauseCount ?? 0) }
    let totalMeasuredPauseDuration = pauseSessions.reduce(0.0) { partial, session in
        let count = max(0, session.pauseCount ?? 0)
        let average = max(0, session.averagePauseSeconds ?? 0)
        return partial + Double(count) * average
    }
    let pausePresentationSeconds = pauseSessions.reduce(0) { $0 + $1.durationSeconds }
    let longestPause = pauseSessions.compactMap(\.longestPauseSeconds).filter { $0.isFinite && $0 >= 0 }.max()

    return LongTermAnalytics(
        sessionCount: measuredSessions.count,
        totalPresentationSeconds: totalDuration,
        averageWPM: durationWeightedAverage(measuredSessions.map {
            WeightedMeasurement(value: $0.averageWPM, weight: $0.durationSeconds)
        }),
        timeInPaceRange: durationWeightedAverage(measuredSessions.map {
            WeightedMeasurement(value: min(1, max(0, $0.timeInPaceRange)), weight: $0.durationSeconds)
        }),
        fillersPerSpeakingMinute: totalSpeaking > 0 ? Double(totalFillers) * 60 / totalSpeaking : 0,
        talkRatio: totalDuration > 0 ? min(1, max(0, totalSpeaking / totalDuration)) : 0,
        onTargetSessionRatio: measuredSessions.isEmpty
            ? 0
            : Double(onTargetCount) / Double(measuredSessions.count),
        averageAbsoluteTimingDeviationSeconds: measuredSessions.isEmpty
            ? 0
            : timingDeviationTotal / Double(measuredSessions.count),
        averagePaceStandardDeviationWPM: paceVariabilityMeasurements.isEmpty
            ? nil
            : durationWeightedAverage(paceVariabilityMeasurements),
        averagePitchRangeSemitones: arithmeticMean(pitchMeasurements),
        averageEnergyRangeDB: arithmeticMean(energyMeasurements),
        measuredIntonationSessionCount: pitchMeasurements.count,
        pausesPerPresentationMinute: pauseSessions.isEmpty || pausePresentationSeconds <= 0
            ? nil
            : Double(totalPauseCount) * 60 / pausePresentationSeconds,
        averagePauseSeconds: pauseSessions.isEmpty || totalPauseCount == 0
            ? nil
            : totalMeasuredPauseDuration / Double(totalPauseCount),
        longestPauseSeconds: pauseSessions.isEmpty ? nil : longestPause,
        measuredPauseSessionCount: pauseSessions.count
    )
}

private struct WeightedMeasurement {
    let value: Double
    let weight: Double
}

private func durationWeightedAverage(_ measurements: [WeightedMeasurement]) -> Double {
    let valid = measurements.filter { measurement in
        measurement.value.isFinite && measurement.weight.isFinite && measurement.weight > 0
    }
    let totalWeight = valid.reduce(0) { $0 + $1.weight }
    guard totalWeight > 0 else { return 0 }
    return valid.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
}

private func arithmeticMean(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
}
