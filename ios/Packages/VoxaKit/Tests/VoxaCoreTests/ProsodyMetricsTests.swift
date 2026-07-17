import Foundation
import Testing
@testable import VoxaCore

private let pitchConfiguration = YINPitchConfiguration.voxaV1()

@Test("YIN estimator tracks presentation-range sine waves")
func yinEstimatorTracksSineWaves() {
    for frequency in [100.0, 150.0, 220.0] {
        let estimate = estimatePitchYIN(
            samples: sineWave(frequency: frequency, count: 640, sampleRate: 16_000, amplitude: 0.5),
            configuration: pitchConfiguration
        )

        #expect(estimate.frequencyHertz != nil)
        #expect(abs((estimate.frequencyHertz ?? 0) - frequency) < 4)
        #expect(estimate.confidence >= pitchConfiguration.minimumConfidence)
    }
}

@Test("Accelerated YIN preserves scalar estimator output")
func acceleratedYINMatchesScalarReference() {
    for frequency in [82.0, 117.5, 150.0, 233.0, 340.0] {
        let samples = harmonicWave(
            frequency: frequency,
            count: 640,
            sampleRate: 16_000
        )
        let accelerated = estimatePitchYIN(samples: samples, configuration: pitchConfiguration)
        let scalar = scalarPitchEstimate(samples: samples, configuration: pitchConfiguration)

        #expect(accelerated.frequencyHertz != nil)
        #expect(scalar.frequencyHertz != nil)
        #expect(abs((accelerated.frequencyHertz ?? 0) - (scalar.frequencyHertz ?? 0)) < 0.001)
        #expect(abs(accelerated.confidence - scalar.confidence) < 0.000_001)
        #expect(abs(accelerated.rms - scalar.rms) < 0.000_001)
    }
}

@Test("YIN estimator rejects silence and low-level audio")
func yinEstimatorRejectsUnvoicedFrames() {
    let silence = estimatePitchYIN(
        samples: Array(repeating: 0, count: 640),
        configuration: pitchConfiguration
    )
    let quiet = estimatePitchYIN(
        samples: sineWave(frequency: 150, count: 640, sampleRate: 16_000, amplitude: 0.001),
        configuration: pitchConfiguration
    )

    #expect(silence.frequencyHertz == nil)
    #expect(quiet.frequencyHertz == nil)
}

@Test("Prosody summary reports low flat variation and high alternating variation")
func prosodySummarySeparatesFlatAndVariedPitch() {
    let flatFrames = (0..<50).map { index in
        ProsodyFrame(
            timestampSeconds: Double(index) * 0.02,
            pitchHertz: 150,
            pitchConfidence: 0.95,
            rms: 0.1,
            decibels: -20
        )
    }
    let variedFrames = (0..<50).map { index in
        ProsodyFrame(
            timestampSeconds: Double(index) * 0.02,
            pitchHertz: index.isMultiple(of: 2) ? 100 : 220,
            pitchConfidence: 0.95,
            rms: 0.1,
            decibels: -20
        )
    }

    let flat = summarizeProsody(frames: flatFrames, minimumPitchConfidence: 0.68)
    let varied = summarizeProsody(frames: variedFrames, minimumPitchConfidence: 0.68)

    #expect(flat.pitchStandardDeviationSemitones < 0.01)
    #expect(flat.pitchRangeSemitones < 0.01)
    #expect(varied.pitchStandardDeviationSemitones > 5)
    #expect(varied.pitchRangeSemitones > 10)
}

@Test("Streaming prosody is invariant to microphone buffer boundaries")
func streamingProsodyHandlesIrregularChunks() {
    let samples = sineWave(frequency: 150, count: 4_800, sampleRate: 16_000, amplitude: 0.5)
    var contiguous = ProsodyStreamAnalyzer(configuration: .voxaV1())
    var chunked = ProsodyStreamAnalyzer(configuration: .voxaV1())

    let contiguousSnapshots = contiguous.consume(samples: samples)
    var chunkedSnapshots: [ProsodySnapshot] = []
    var index = 0
    for chunkSize in [173, 811, 97, 1_109, 263, 701, 1_646] where index < samples.count {
        let end = min(samples.count, index + chunkSize)
        chunkedSnapshots.append(contentsOf: chunked.consume(samples: Array(samples[index..<end])))
        index = end
    }
    if index < samples.count {
        chunkedSnapshots.append(contentsOf: chunked.consume(samples: Array(samples[index...])))
    }

    #expect(chunkedSnapshots.count == contiguousSnapshots.count)
    #expect(chunkedSnapshots.last?.voicedFrameCount == contiguousSnapshots.last?.voicedFrameCount)
    #expect(abs((chunkedSnapshots.last?.currentPitchHertz ?? 0) - 150) < 4)
}

@Test("Streaming prosody keeps four-times realtime processing headroom")
func streamingProsodyKeepsRealtimeHeadroom() {
    let sampleRate = 16_000.0
    let audioDurationSeconds = 3.2
    let samples = sineWave(
        frequency: 150,
        count: Int(sampleRate * audioDurationSeconds),
        sampleRate: sampleRate,
        amplitude: 0.5
    )
    var analyzer = ProsodyStreamAnalyzer(configuration: .voxaV1())
    let started = ContinuousClock.now
    var snapshots: [ProsodySnapshot] = []

    for chunkStart in stride(from: 0, to: samples.count, by: 1_600) {
        let chunkEnd = min(samples.count, chunkStart + 1_600)
        snapshots.append(
            contentsOf: analyzer.consume(samples: Array(samples[chunkStart..<chunkEnd]))
        )
    }

    let elapsed = started.duration(to: .now)
    #expect(snapshots.count == 31)
    #expect(abs((snapshots.last?.currentPitchHertz ?? 0) - 150) < 4)
    #expect(elapsed < .milliseconds(800))
}

@Test("Local voice activity produces speaking time and an internal pause")
func localVoiceActivityProducesUsableTiming() throws {
    let sampleRate = 16_000.0
    let samples = Array(repeating: Float.zero, count: 8_000)
        + sineWave(frequency: 150, count: 16_000, sampleRate: sampleRate, amplitude: 0.08)
        + Array(repeating: Float.zero, count: 12_800)
        + sineWave(frequency: 170, count: 16_000, sampleRate: sampleRate, amplitude: 0.08)
    var analyzer = VoiceActivityStreamAnalyzer(configuration: .voxaV1())

    let frames = analyzer.consume(samples: samples)
    let speakingSeconds = frames.filter(\.isSpeech).reduce(0.0) { partial, frame in
        partial + frame.endSeconds - frame.startSeconds
    }
    let pauses = internalPauseDurations(
        intervals: frames.map {
            SpeechActivityInterval(
                isSpeech: $0.isSpeech,
                startSeconds: $0.startSeconds,
                endSeconds: $0.endSeconds
            )
        },
        minimumDurationSeconds: 0.5
    )

    #expect(speakingSeconds > 1.8)
    #expect(speakingSeconds < 2.2)
    #expect(pauses.count == 1)
    #expect(try #require(pauses.first) > 0.6)
}

@Test("Local voice activity is invariant to microphone buffer boundaries")
func localVoiceActivityHandlesIrregularChunks() {
    let sampleRate = 16_000.0
    let samples = Array(repeating: Float.zero, count: 6_400)
        + sineWave(frequency: 150, count: 19_200, sampleRate: sampleRate, amplitude: 0.06)
        + Array(repeating: Float.zero, count: 8_000)
    var contiguous = VoiceActivityStreamAnalyzer(configuration: .voxaV1())
    var chunked = VoiceActivityStreamAnalyzer(configuration: .voxaV1())

    let contiguousFrames = contiguous.consume(samples: samples)
    var chunkedFrames: [VoiceActivityFrame] = []
    var index = 0
    for chunkSize in [173, 811, 97, 1_109, 263, 701, 1_646] {
        guard index < samples.count else { break }
        let end = min(samples.count, index + chunkSize)
        chunkedFrames.append(contentsOf: chunked.consume(samples: Array(samples[index..<end])))
        index = end
    }
    if index < samples.count {
        chunkedFrames.append(contentsOf: chunked.consume(samples: Array(samples[index...])))
    }

    #expect(chunkedFrames == contiguousFrames)
    #expect(chunkedFrames.contains { $0.isSpeech })
}

@Test("Local voice activity detects a presenter who starts immediately")
func localVoiceActivityDetectsImmediateSpeech() throws {
    let samples = sineWave(
        frequency: 150,
        count: 16_000,
        sampleRate: 16_000,
        amplitude: 0.08
    )
    var analyzer = VoiceActivityStreamAnalyzer(configuration: .voxaV1())

    let frames = analyzer.consume(samples: samples)
    let firstSpeech = try #require(frames.first { $0.isSpeech })

    #expect(firstSpeech.startSeconds < 0.1)
}

private func sineWave(
    frequency: Double,
    count: Int,
    sampleRate: Double,
    amplitude: Double
) -> [Float] {
    (0..<count).map { index in
        Float(amplitude * sin(2 * Double.pi * frequency * Double(index) / sampleRate))
    }
}

private func harmonicWave(
    frequency: Double,
    count: Int,
    sampleRate: Double
) -> [Float] {
    (0..<count).map { index in
        let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
        return Float(
            0.55 * sin(phase)
                + 0.18 * sin(2 * phase + 0.3)
                + 0.07 * sin(3 * phase + 0.8)
        )
    }
}

private func scalarPitchEstimate(
    samples: [Float],
    configuration: YINPitchConfiguration
) -> PitchEstimate {
    let sumSquares = samples.reduce(0.0) { partial, sample in
        partial + Double(sample) * Double(sample)
    }
    let rms = Float(sqrt(sumSquares / Double(samples.count)))
    let minimumLag = max(2, Int(floor(configuration.sampleRate / configuration.maximumPitchHertz)))
    let maximumLag = min(
        samples.count - 2,
        Int(ceil(configuration.sampleRate / configuration.minimumPitchHertz))
    )
    var difference = Array(repeating: 0.0, count: maximumLag + 1)
    for lag in 1...maximumLag {
        var sum = 0.0
        for index in 0..<(samples.count - lag) {
            let delta = Double(samples[index] - samples[index + lag])
            sum += delta * delta
        }
        difference[lag] = sum
    }

    var normalized = Array(repeating: 1.0, count: maximumLag + 1)
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
    let previous = normalized[selectedLag - 1]
    let current = normalized[selectedLag]
    let next = normalized[selectedLag + 1]
    let denominator = previous - 2 * current + next
    let adjustment = abs(denominator) > .ulpOfOne
        ? min(1, max(-1, 0.5 * (previous - next) / denominator))
        : 0
    let frequency = configuration.sampleRate / (Double(selectedLag) + adjustment)
    return PitchEstimate(frequencyHertz: frequency, confidence: confidence, rms: rms)
}
