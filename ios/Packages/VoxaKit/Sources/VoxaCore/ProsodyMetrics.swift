import Accelerate
import Foundation

public struct YINPitchConfiguration: Equatable, Sendable {
    public let sampleRate: Double
    public let minimumPitchHertz: Double
    public let maximumPitchHertz: Double
    public let minimumRMS: Float
    public let troughThreshold: Double
    public let minimumConfidence: Double

    public init(
        sampleRate: Double,
        minimumPitchHertz: Double,
        maximumPitchHertz: Double,
        minimumRMS: Float,
        troughThreshold: Double,
        minimumConfidence: Double
    ) {
        self.sampleRate = sampleRate
        self.minimumPitchHertz = minimumPitchHertz
        self.maximumPitchHertz = maximumPitchHertz
        self.minimumRMS = minimumRMS
        self.troughThreshold = troughThreshold
        self.minimumConfidence = minimumConfidence
    }

    public static func voxaV1() -> YINPitchConfiguration {
        YINPitchConfiguration(
            sampleRate: 16_000,
            minimumPitchHertz: 75,
            maximumPitchHertz: 350,
            minimumRMS: 0.006,
            troughThreshold: 0.15,
            minimumConfidence: 0.68
        )
    }
}

public struct PitchEstimate: Equatable, Sendable {
    public let frequencyHertz: Double?
    public let confidence: Double
    public let rms: Float

    public init(frequencyHertz: Double?, confidence: Double, rms: Float) {
        self.frequencyHertz = frequencyHertz
        self.confidence = confidence
        self.rms = rms
    }
}

public struct ProsodyConfiguration: Equatable, Sendable {
    public let pitch: YINPitchConfiguration
    public let frameSampleCount: Int
    public let hopSampleCount: Int
    public let rollingWindowSeconds: TimeInterval
    public let publishEveryHops: Int

    public init(
        pitch: YINPitchConfiguration,
        frameSampleCount: Int,
        hopSampleCount: Int,
        rollingWindowSeconds: TimeInterval,
        publishEveryHops: Int
    ) {
        self.pitch = pitch
        self.frameSampleCount = frameSampleCount
        self.hopSampleCount = hopSampleCount
        self.rollingWindowSeconds = rollingWindowSeconds
        self.publishEveryHops = publishEveryHops
    }

    public static func voxaV1() -> ProsodyConfiguration {
        ProsodyConfiguration(
            pitch: .voxaV1(),
            frameSampleCount: 640,
            hopSampleCount: 320,
            rollingWindowSeconds: 8,
            publishEveryHops: 5
        )
    }
}

public struct ProsodyFrame: Equatable, Sendable {
    public let timestampSeconds: TimeInterval
    public let pitchHertz: Double?
    public let pitchConfidence: Double
    public let rms: Float
    public let decibels: Double

    public init(
        timestampSeconds: TimeInterval,
        pitchHertz: Double?,
        pitchConfidence: Double,
        rms: Float,
        decibels: Double
    ) {
        self.timestampSeconds = timestampSeconds
        self.pitchHertz = pitchHertz
        self.pitchConfidence = pitchConfidence
        self.rms = rms
        self.decibels = decibels
    }
}

public struct ProsodySnapshot: Equatable, Sendable {
    public let currentPitchHertz: Double?
    public let pitchConfidence: Double
    public let rms: Float
    public let decibels: Double
    public let pitchStandardDeviationSemitones: Double
    public let pitchRangeSemitones: Double
    public let loudnessStandardDeviationDB: Double
    public let voicedRatio: Double
    public let voicedFrameCount: Int

    public init(
        currentPitchHertz: Double?,
        pitchConfidence: Double,
        rms: Float,
        decibels: Double,
        pitchStandardDeviationSemitones: Double,
        pitchRangeSemitones: Double,
        loudnessStandardDeviationDB: Double,
        voicedRatio: Double,
        voicedFrameCount: Int
    ) {
        self.currentPitchHertz = currentPitchHertz
        self.pitchConfidence = pitchConfidence
        self.rms = rms
        self.decibels = decibels
        self.pitchStandardDeviationSemitones = pitchStandardDeviationSemitones
        self.pitchRangeSemitones = pitchRangeSemitones
        self.loudnessStandardDeviationDB = loudnessStandardDeviationDB
        self.voicedRatio = voicedRatio
        self.voicedFrameCount = voicedFrameCount
    }
}

public func estimatePitchYIN(
    samples: [Float],
    configuration: YINPitchConfiguration
) -> PitchEstimate {
    var estimator = YINPitchEstimator()
    return samples.withUnsafeBufferPointer { buffer in
        estimator.estimate(samples: buffer, configuration: configuration)
    }
}

private struct YINPitchEstimator: Sendable {
    private var doubleSamples: [Double] = []
    private var squaredPrefixSums: [Double] = []
    private var difference: [Double] = []
    private var normalized: [Double] = []

    mutating func estimate(
        samples: UnsafeBufferPointer<Float>,
        configuration: YINPitchConfiguration
    ) -> PitchEstimate {
        guard configuration.sampleRate.isFinite,
              configuration.sampleRate > 0,
              configuration.minimumPitchHertz > 0,
              configuration.maximumPitchHertz > configuration.minimumPitchHertz,
              samples.count >= 3 else {
            return PitchEstimate(frequencyHertz: nil, confidence: 0, rms: 0)
        }

        let rms = rootMeanSquare(samples)
        guard rms.isFinite, rms >= configuration.minimumRMS else {
            return PitchEstimate(frequencyHertz: nil, confidence: 0, rms: rms.isFinite ? rms : 0)
        }

        let minimumLag = max(2, Int(floor(configuration.sampleRate / configuration.maximumPitchHertz)))
        let maximumLag = min(
            samples.count - 2,
            Int(ceil(configuration.sampleRate / configuration.minimumPitchHertz))
        )
        guard minimumLag < maximumLag else {
            return PitchEstimate(frequencyHertz: nil, confidence: 0, rms: rms)
        }

        prepareScratch(sampleCount: samples.count, maximumLag: maximumLag)
        if let source = samples.baseAddress {
            doubleSamples.withUnsafeMutableBufferPointer { converted in
                guard let destination = converted.baseAddress else { return }
                vDSP_vspdp(source, 1, destination, 1, vDSP_Length(samples.count))
            }
        }
        squaredPrefixSums[0] = 0
        for index in 0..<samples.count {
            let sample = doubleSamples[index]
            squaredPrefixSums[index + 1] = squaredPrefixSums[index] + sample * sample
        }
        doubleSamples.withUnsafeBufferPointer { converted in
            guard let base = converted.baseAddress else { return }
            for lag in 1...maximumLag {
                let comparedCount = samples.count - lag
                var crossCorrelation = 0.0
                vDSP_dotprD(
                    base,
                    1,
                    base.advanced(by: lag),
                    1,
                    &crossCorrelation,
                    vDSP_Length(comparedCount)
                )
                let leadingEnergy = squaredPrefixSums[comparedCount]
                let trailingEnergy = squaredPrefixSums[samples.count] - squaredPrefixSums[lag]
                difference[lag] = max(0, leadingEnergy + trailingEnergy - 2 * crossCorrelation)
            }
        }

        normalized[0] = 1
        var cumulativeDifference = 0.0
        for lag in 1...maximumLag {
            cumulativeDifference += difference[lag]
            normalized[lag] = cumulativeDifference > 0
                ? difference[lag] * Double(lag) / cumulativeDifference
                : 1
        }

        var selectedLag: Int?
        var lag = minimumLag
        while lag <= maximumLag {
            if normalized[lag] < configuration.troughThreshold {
                while lag < maximumLag, normalized[lag + 1] < normalized[lag] {
                    lag += 1
                }
                selectedLag = lag
                break
            }
            lag += 1
        }
        guard let selectedLag else {
            return PitchEstimate(frequencyHertz: nil, confidence: 0, rms: rms)
        }

        let confidence = min(1, max(0, 1 - normalized[selectedLag]))
        guard confidence >= configuration.minimumConfidence else {
            return PitchEstimate(frequencyHertz: nil, confidence: confidence, rms: rms)
        }

        let refinedLag = parabolicLag(values: normalized, index: selectedLag)
        guard refinedLag.isFinite, refinedLag > 0 else {
            return PitchEstimate(frequencyHertz: nil, confidence: confidence, rms: rms)
        }
        let frequency = configuration.sampleRate / refinedLag
        guard frequency >= configuration.minimumPitchHertz,
              frequency <= configuration.maximumPitchHertz else {
            return PitchEstimate(frequencyHertz: nil, confidence: confidence, rms: rms)
        }
        return PitchEstimate(frequencyHertz: frequency, confidence: confidence, rms: rms)
    }

    private mutating func prepareScratch(sampleCount: Int, maximumLag: Int) {
        if doubleSamples.count < sampleCount {
            doubleSamples = Array(repeating: 0, count: sampleCount)
            squaredPrefixSums = Array(repeating: 0, count: sampleCount + 1)
        }
        if difference.count < maximumLag + 1 {
            difference = Array(repeating: 0, count: maximumLag + 1)
            normalized = Array(repeating: 1, count: maximumLag + 1)
        }
    }
}

public func summarizeProsody(
    frames: [ProsodyFrame],
    minimumPitchConfidence: Double
) -> ProsodySnapshot {
    guard let latest = frames.last else {
        return ProsodySnapshot(
            currentPitchHertz: nil,
            pitchConfidence: 0,
            rms: 0,
            decibels: -120,
            pitchStandardDeviationSemitones: 0,
            pitchRangeSemitones: 0,
            loudnessStandardDeviationDB: 0,
            voicedRatio: 0,
            voicedFrameCount: 0
        )
    }
    let voiced = frames.filter { frame in
        frame.pitchHertz != nil && frame.pitchConfidence >= minimumPitchConfidence
    }
    let pitches = voiced.compactMap(\.pitchHertz)
    guard !pitches.isEmpty else {
        return ProsodySnapshot(
            currentPitchHertz: latest.pitchHertz,
            pitchConfidence: latest.pitchConfidence,
            rms: latest.rms,
            decibels: latest.decibels,
            pitchStandardDeviationSemitones: 0,
            pitchRangeSemitones: 0,
            loudnessStandardDeviationDB: 0,
            voicedRatio: 0,
            voicedFrameCount: 0
        )
    }

    let baseline = percentile(pitches, fraction: 0.5)
    let semitones = pitches.map { 12 * log2($0 / baseline) }.filter(\.isFinite)
    let voicedDecibels = voiced.map(\.decibels).filter(\.isFinite)
    return ProsodySnapshot(
        currentPitchHertz: latest.pitchHertz,
        pitchConfidence: latest.pitchConfidence,
        rms: latest.rms,
        decibels: latest.decibels,
        pitchStandardDeviationSemitones: standardDeviation(semitones),
        pitchRangeSemitones: percentile(semitones, fraction: 0.9) - percentile(semitones, fraction: 0.1),
        loudnessStandardDeviationDB: standardDeviation(voicedDecibels),
        voicedRatio: Double(voiced.count) / Double(frames.count),
        voicedFrameCount: voiced.count
    )
}

public struct VoiceActivityConfiguration: Equatable, Sendable {
    public let sampleRate: Double
    public let frameSampleCount: Int
    public let hopSampleCount: Int
    public let calibrationFrameCount: Int
    public let initialNoiseFloorDB: Double
    public let absoluteSpeechOnDB: Double
    public let absoluteSpeechOffDB: Double
    public let speechToNoiseOnDB: Double
    public let speechToNoiseOffDB: Double
    public let activationFrameCount: Int
    public let releaseFrameCount: Int
    public let noiseAdaptation: Double

    public init(
        sampleRate: Double,
        frameSampleCount: Int,
        hopSampleCount: Int,
        calibrationFrameCount: Int,
        initialNoiseFloorDB: Double,
        absoluteSpeechOnDB: Double,
        absoluteSpeechOffDB: Double,
        speechToNoiseOnDB: Double,
        speechToNoiseOffDB: Double,
        activationFrameCount: Int,
        releaseFrameCount: Int,
        noiseAdaptation: Double
    ) {
        self.sampleRate = sampleRate
        self.frameSampleCount = frameSampleCount
        self.hopSampleCount = hopSampleCount
        self.calibrationFrameCount = calibrationFrameCount
        self.initialNoiseFloorDB = initialNoiseFloorDB
        self.absoluteSpeechOnDB = absoluteSpeechOnDB
        self.absoluteSpeechOffDB = absoluteSpeechOffDB
        self.speechToNoiseOnDB = speechToNoiseOnDB
        self.speechToNoiseOffDB = speechToNoiseOffDB
        self.activationFrameCount = activationFrameCount
        self.releaseFrameCount = releaseFrameCount
        self.noiseAdaptation = noiseAdaptation
    }

    public static func voxaV1() -> VoiceActivityConfiguration {
        VoiceActivityConfiguration(
            sampleRate: 16_000,
            frameSampleCount: 320,
            hopSampleCount: 320,
            calibrationFrameCount: 15,
            initialNoiseFloorDB: -60,
            absoluteSpeechOnDB: -48,
            absoluteSpeechOffDB: -54,
            speechToNoiseOnDB: 8,
            speechToNoiseOffDB: 5,
            activationFrameCount: 2,
            releaseFrameCount: 5,
            noiseAdaptation: 0.15
        )
    }
}

public struct VoiceActivityFrame: Equatable, Sendable {
    public let isSpeech: Bool
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval

    public init(isSpeech: Bool, startSeconds: TimeInterval, endSeconds: TimeInterval) {
        self.isSpeech = isSpeech
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

public struct VoiceActivityStreamAnalyzer: Sendable {
    private let configuration: VoiceActivityConfiguration
    private var samples: [Float] = []
    private var readIndex = 0
    private var processedFrameCount = 0
    private var noiseFloorDB: Double
    private var isSpeech = false
    private var activationCount = 0
    private var releaseCount = 0

    public init(configuration: VoiceActivityConfiguration) {
        self.configuration = configuration
        self.noiseFloorDB = configuration.initialNoiseFloorDB
    }

    public mutating func consume(samples incomingSamples: [Float]) -> [VoiceActivityFrame] {
        guard configuration.sampleRate.isFinite,
              configuration.sampleRate > 0,
              configuration.frameSampleCount > 0,
              configuration.hopSampleCount > 0,
              configuration.activationFrameCount > 0,
              configuration.releaseFrameCount > 0,
              configuration.noiseAdaptation >= 0,
              configuration.noiseAdaptation <= 1 else {
            return []
        }
        samples.append(contentsOf: incomingSamples)
        var frames: [VoiceActivityFrame] = []

        while samples.count - readIndex >= configuration.frameSampleCount {
            let rms = samples.withUnsafeBufferPointer { buffer in
                rootMeanSquare(
                    UnsafeBufferPointer(
                        start: buffer.baseAddress?.advanced(by: readIndex),
                        count: configuration.frameSampleCount
                    )
                )
            }
            let decibels = rms > 0 ? 20 * log10(Double(rms)) : -120
            updateState(decibels: decibels)

            let startSeconds = Double(processedFrameCount * configuration.hopSampleCount)
                / configuration.sampleRate
            let endSeconds = startSeconds
                + Double(configuration.frameSampleCount) / configuration.sampleRate
            frames.append(
                VoiceActivityFrame(
                    isSpeech: isSpeech,
                    startSeconds: startSeconds,
                    endSeconds: endSeconds
                )
            )
            processedFrameCount += 1
            readIndex += configuration.hopSampleCount
        }

        if readIndex >= 4_096 {
            samples.removeFirst(readIndex)
            readIndex = 0
        }
        return frames
    }

    private mutating func updateState(decibels: Double) {
        if processedFrameCount < configuration.calibrationFrameCount,
           decibels < configuration.absoluteSpeechOffDB {
            updateNoiseFloor(decibels: decibels)
            isSpeech = false
            activationCount = 0
            releaseCount = 0
            return
        }

        if isSpeech {
            let speechOffThreshold = max(
                configuration.absoluteSpeechOffDB,
                noiseFloorDB + configuration.speechToNoiseOffDB
            )
            if decibels < speechOffThreshold {
                releaseCount += 1
                if releaseCount >= configuration.releaseFrameCount {
                    isSpeech = false
                    releaseCount = 0
                    activationCount = 0
                    updateNoiseFloor(decibels: decibels)
                }
            } else {
                releaseCount = 0
            }
            return
        }

        let speechOnThreshold = max(
            configuration.absoluteSpeechOnDB,
            noiseFloorDB + configuration.speechToNoiseOnDB
        )
        if decibels >= speechOnThreshold {
            activationCount += 1
            if activationCount >= configuration.activationFrameCount {
                isSpeech = true
                activationCount = 0
                releaseCount = 0
            }
        } else {
            activationCount = 0
            updateNoiseFloor(decibels: decibels)
        }
    }

    private mutating func updateNoiseFloor(decibels: Double) {
        let boundedDecibels = min(-20, max(-120, decibels))
        noiseFloorDB = noiseFloorDB * (1 - configuration.noiseAdaptation)
            + boundedDecibels * configuration.noiseAdaptation
    }
}

public struct ProsodyStreamAnalyzer: Sendable {
    private let configuration: ProsodyConfiguration
    private var pitchEstimator = YINPitchEstimator()
    private var samples: [Float] = []
    private var readIndex = 0
    private var processedHopCount = 0
    private var frames: [ProsodyFrame] = []

    public init(configuration: ProsodyConfiguration) {
        self.configuration = configuration
    }

    public mutating func consume(samples incomingSamples: [Float]) -> [ProsodySnapshot] {
        guard configuration.frameSampleCount > 0,
              configuration.hopSampleCount > 0,
              configuration.publishEveryHops > 0 else { return [] }
        samples.append(contentsOf: incomingSamples)
        var snapshots: [ProsodySnapshot] = []

        while samples.count - readIndex >= configuration.frameSampleCount {
            let estimate = samples.withUnsafeBufferPointer { buffer in
                let frameStart = buffer.baseAddress?.advanced(by: readIndex)
                return pitchEstimator.estimate(
                    samples: UnsafeBufferPointer(start: frameStart, count: configuration.frameSampleCount),
                    configuration: configuration.pitch
                )
            }
            let timestamp = Double(processedHopCount * configuration.hopSampleCount)
                / configuration.pitch.sampleRate
            let decibels = estimate.rms > 0 ? 20 * log10(Double(estimate.rms)) : -120
            frames.append(
                ProsodyFrame(
                    timestampSeconds: timestamp,
                    pitchHertz: estimate.frequencyHertz,
                    pitchConfidence: estimate.confidence,
                    rms: estimate.rms,
                    decibels: decibels
                )
            )
            frames.removeAll { $0.timestampSeconds < timestamp - configuration.rollingWindowSeconds }
            processedHopCount += 1
            readIndex += configuration.hopSampleCount

            if processedHopCount.isMultiple(of: configuration.publishEveryHops) {
                snapshots.append(
                    summarizeProsody(
                        frames: frames,
                        minimumPitchConfidence: configuration.pitch.minimumConfidence
                    )
                )
            }
        }

        if readIndex >= 4_096 {
            samples.removeFirst(readIndex)
            readIndex = 0
        }
        return snapshots
    }
}

private func rootMeanSquare(_ samples: UnsafeBufferPointer<Float>) -> Float {
    guard !samples.isEmpty else { return 0 }
    let sumSquares = samples.reduce(0.0) { partial, sample in
        partial + Double(sample) * Double(sample)
    }
    return Float(sqrt(sumSquares / Double(samples.count)))
}

private func parabolicLag(values: [Double], index: Int) -> Double {
    guard index > 0, index + 1 < values.count else { return Double(index) }
    let previous = values[index - 1]
    let current = values[index]
    let next = values[index + 1]
    let denominator = previous - 2 * current + next
    guard abs(denominator) > .ulpOfOne else { return Double(index) }
    let adjustment = 0.5 * (previous - next) / denominator
    return Double(index) + min(1, max(-1, adjustment))
}

private func percentile(_ values: [Double], fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let boundedFraction = min(1, max(0, fraction))
    let position = boundedFraction * Double(sorted.count - 1)
    let lower = Int(floor(position))
    let upper = Int(ceil(position))
    if lower == upper { return sorted[lower] }
    let weight = position - Double(lower)
    return sorted[lower] * (1 - weight) + sorted[upper] * weight
}

private func standardDeviation(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { partial, value in
        partial + (value - mean) * (value - mean)
    } / Double(values.count)
    return sqrt(max(0, variance))
}
