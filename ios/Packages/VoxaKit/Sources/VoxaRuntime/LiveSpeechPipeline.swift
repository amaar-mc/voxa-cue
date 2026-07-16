import AVFoundation
import CoreMedia
import Foundation
import Speech
import Synchronization

public enum LiveSpeechPipelineError: Error, Equatable {
    case permissionDenied
    case transcriberUnavailable
    case unsupportedLocale
    case speechAssetsUnavailable
    case noCompatibleAudioFormat
    case bufferAllocationFailed
    case conversionFailed
    case alreadyRunning
    case invalidInputFormat
}

public enum LiveSpeechEvent: Sendable {
    case volatileTranscript(text: String, startSeconds: TimeInterval, endSeconds: TimeInterval)
    case finalizedTranscript(text: String, startSeconds: TimeInterval, endSeconds: TimeInterval)
    case voiceActivity(isSpeech: Bool, durationSeconds: TimeInterval)
    case vocalSample(energyDBFS: Double, pitchHertz: Double?)
    case failure(message: String)
}

@MainActor
public final class LiveSpeechPipeline {
    public typealias EventHandler = @MainActor @Sendable (LiveSpeechEvent) -> Void

    private let audioEngine: AVAudioEngine
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var detector: SpeechDetector?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var bufferContinuation: AsyncStream<SendableAudioBuffer>.Continuation?
    private var analyzerTask: Task<Void, Never>?
    private var bufferTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?
    private var eventHandler: EventHandler?
    private var tapInstalled = false
    private let captureGate = AudioCaptureGate()

    public init(audioEngine: AVAudioEngine) {
        self.audioEngine = audioEngine
    }

    deinit {
        analyzerTask?.cancel()
        bufferTask?.cancel()
        transcriptionTask?.cancel()
        detectionTask?.cancel()
        interruptionTask?.cancel()
    }

    public static func requestPermissions() async -> Bool {
        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard microphoneGranted else { return false }
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return speechStatus == .authorized
    }

    public func prepare(localeIdentifier: String) async throws {
        guard SpeechTranscriber.isAvailable else { throw LiveSpeechPipelineError.transcriberUnavailable }
        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw LiveSpeechPipelineError.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let detector = SpeechDetector(
            detectionOptions: SpeechDetector.DetectionOptions(sensitivityLevel: .medium),
            reportResults: true
        )
        let modules: [any SpeechModule] = [transcriber, detector]
        let status = await AssetInventory.status(forModules: modules)
        switch status {
        case .installed:
            break
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
        case .unsupported:
            throw LiveSpeechPipelineError.speechAssetsUnavailable
        @unknown default:
            throw LiveSpeechPipelineError.speechAssetsUnavailable
        }
        self.transcriber = transcriber
        self.detector = detector
    }

    public func start(eventHandler: @escaping EventHandler) async throws {
        guard !tapInstalled, !audioEngine.isRunning, analyzerTask == nil else {
            throw LiveSpeechPipelineError.alreadyRunning
        }
        guard let transcriber, let detector else { throw LiveSpeechPipelineError.transcriberUnavailable }
        let modules: [any SpeechModule] = [transcriber, detector]
        do {
            self.eventHandler = eventHandler
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
                throw LiveSpeechPipelineError.noCompatibleAudioFormat
            }

            #if os(iOS)
            try configureAudioSession()
            #endif

            let analyzer = SpeechAnalyzer(modules: modules)
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
            self.analyzer = analyzer

            let naturalFormat = audioEngine.inputNode.outputFormat(forBus: 0)
            guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
                throw LiveSpeechPipelineError.invalidInputFormat
            }
            let conversionContext = AudioConversionContext(
                converter: AVAudioConverter(from: naturalFormat, to: analyzerFormat),
                outputFormat: analyzerFormat
            )
            if naturalFormat != analyzerFormat, conversionContext.converter == nil {
                throw LiveSpeechPipelineError.conversionFailed
            }

            let inputPair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
            inputContinuation = inputPair.continuation
            analyzerTask = Task { [weak self] in
                do {
                    try await analyzer.start(inputSequence: inputPair.stream)
                } catch where !Task.isCancelled {
                    self?.eventHandler?(.failure(message: error.localizedDescription))
                } catch {
                    return
                }
            }

            transcriptionTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        let text = String(result.text.characters)
                        let start = result.range.start.seconds
                        let end = CMTimeRangeGetEnd(result.range).seconds
                        if result.isFinal {
                            self.eventHandler?(.finalizedTranscript(text: text, startSeconds: start, endSeconds: end))
                        } else {
                            self.eventHandler?(.volatileTranscript(text: text, startSeconds: start, endSeconds: end))
                        }
                    }
                } catch where !Task.isCancelled {
                    self?.eventHandler?(.failure(message: error.localizedDescription))
                } catch {
                    return
                }
            }

            detectionTask = Task { [weak self] in
                do {
                    for try await result in detector.results where result.isFinal {
                        self?.eventHandler?(
                            .voiceActivity(isSpeech: result.speechDetected, durationSeconds: result.range.duration.seconds)
                        )
                    }
                } catch where !Task.isCancelled {
                    self?.eventHandler?(.failure(message: error.localizedDescription))
                } catch {
                    return
                }
            }

            let bufferPair = AsyncStream<SendableAudioBuffer>.makeStream(bufferingPolicy: .bufferingNewest(32))
            bufferContinuation = bufferPair.continuation
            let captureGate = self.captureGate
            bufferTask = Task.detached {
                var timeline = ContiguousAudioTimeline()
                var vocalSampleCounter = 0
                for await item in bufferPair.stream {
                    guard captureGate.isActive(generation: item.captureGeneration) else { continue }
                    do {
                        let converted = try convert(
                            input: item.buffer,
                            converter: conversionContext.converter,
                            outputFormat: conversionContext.outputFormat
                        )
                        guard captureGate.isActive(generation: item.captureGeneration) else { continue }
                        let startSeconds = timeline.consume(
                            frameCount: Int(converted.frameLength),
                            sampleRate: converted.format.sampleRate
                        )
                        let startTime = CMTime(seconds: startSeconds, preferredTimescale: 48_000)
                        inputPair.continuation.yield(AnalyzerInput(buffer: converted, bufferStartTime: startTime))
                        vocalSampleCounter += 1
                        if vocalSampleCounter.isMultiple(of: 5), let sample = analyzeVocalBuffer(item.buffer) {
                            await eventHandler(.vocalSample(energyDBFS: sample.energyDBFS, pitchHertz: sample.pitchHertz))
                        }
                    } catch {
                        await eventHandler(.failure(message: error.localizedDescription))
                    }
                }
                inputPair.continuation.finish()
            }

            captureGate.start()
            audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1_024, format: naturalFormat) { buffer, _ in
                guard let captureGeneration = captureGate.generationForCapture() else { return }
                guard let copy = copiedBuffer(buffer) else { return }
                bufferPair.continuation.yield(
                    SendableAudioBuffer(buffer: copy, captureGeneration: captureGeneration)
                )
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            #if os(iOS)
            observeAudioInterruptions()
            #endif
        } catch {
            await rollbackFailedStart()
            throw error
        }
    }

    public func pauseCapture() {
        captureGate.pause()
    }

    public func resumeCapture() {
        captureGate.resume()
    }

    public func stop() async {
        captureGate.stop()
        interruptionTask?.cancel()
        interruptionTask = nil
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        bufferContinuation?.finish()
        await bufferTask?.value
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
            }
        }
        await analyzerTask?.value
        await transcriptionTask?.value
        await detectionTask?.value
        clearRuntimeState()
        deactivateAudioSession()
    }

    private func rollbackFailedStart() async {
        captureGate.stop()
        interruptionTask?.cancel()
        interruptionTask = nil
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        bufferContinuation?.finish()
        inputContinuation?.finish()
        analyzerTask?.cancel()
        bufferTask?.cancel()
        transcriptionTask?.cancel()
        detectionTask?.cancel()
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        clearRuntimeState()
        deactivateAudioSession()
    }

    private func clearRuntimeState() {
        inputContinuation = nil
        bufferContinuation = nil
        analyzerTask = nil
        bufferTask = nil
        transcriptionTask = nil
        detectionTask = nil
        interruptionTask = nil
        self.analyzer = nil
        eventHandler = nil
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    #if os(iOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        if let builtInMicrophone = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(builtInMicrophone)
        }
        try session.setActive(true)
    }

    private func observeAudioInterruptions() {
        interruptionTask?.cancel()
        interruptionTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                guard !Task.isCancelled,
                      let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: rawValue) == .began else {
                    continue
                }
                self?.eventHandler?(.failure(message: "Audio capture was interrupted by another app or system event."))
            }
        }
    }
    #endif
}

private final class SendableAudioBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let captureGeneration: UInt64

    init(buffer: AVAudioPCMBuffer, captureGeneration: UInt64) {
        self.buffer = buffer
        self.captureGeneration = captureGeneration
    }
}

private final class AudioConversionContext: @unchecked Sendable {
    let converter: AVAudioConverter?
    let outputFormat: AVAudioFormat

    init(converter: AVAudioConverter?, outputFormat: AVAudioFormat) {
        self.converter = converter
        self.outputFormat = outputFormat
    }
}

private struct AudioCaptureState: Sendable {
    var isEnabled: Bool
    var generation: UInt64
}

private final class AudioCaptureGate: Sendable {
    private let state = Mutex(AudioCaptureState(isEnabled: false, generation: 0))

    func start() {
        state.withLock { state in
            state.generation &+= 1
            state.isEnabled = true
        }
    }

    func pause() {
        state.withLock { state in
            guard state.isEnabled else { return }
            state.generation &+= 1
            state.isEnabled = false
        }
    }

    func resume() {
        state.withLock { state in
            guard !state.isEnabled else { return }
            state.generation &+= 1
            state.isEnabled = true
        }
    }

    func stop() {
        state.withLock { state in
            state.generation &+= 1
            state.isEnabled = false
        }
    }

    func generationForCapture() -> UInt64? {
        state.withLock { state in
            state.isEnabled ? state.generation : nil
        }
    }

    func isActive(generation: UInt64) -> Bool {
        state.withLock { state in
            state.isEnabled && state.generation == generation
        }
    }
}

private struct VocalSample {
    let energyDBFS: Double
    let pitchHertz: Double?
}

private func copiedBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
    copy.frameLength = source.frameLength
    let sourceList = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
    let destinationList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for index in 0..<min(sourceList.count, destinationList.count) {
        guard let sourceData = sourceList[index].mData, let destinationData = destinationList[index].mData else { continue }
        memcpy(destinationData, sourceData, Int(sourceList[index].mDataByteSize))
        destinationList[index].mDataByteSize = sourceList[index].mDataByteSize
    }
    return copy
}

private func convert(
    input: AVAudioPCMBuffer,
    converter: AVAudioConverter?,
    outputFormat: AVAudioFormat
) throws -> AVAudioPCMBuffer {
    if input.format == outputFormat { return input }
    guard let converter else { throw LiveSpeechPipelineError.conversionFailed }
    let ratio = outputFormat.sampleRate / input.format.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
        throw LiveSpeechPipelineError.bufferAllocationFailed
    }
    var suppliedInput = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
        if suppliedInput {
            inputStatus.pointee = .noDataNow
            return nil
        }
        suppliedInput = true
        inputStatus.pointee = .haveData
        return input
    }
    if let conversionError { throw conversionError }
    guard status == .haveData || status == .inputRanDry else { throw LiveSpeechPipelineError.conversionFailed }
    return output
}

private func analyzeVocalBuffer(_ buffer: AVAudioPCMBuffer) -> VocalSample? {
    guard let channel = buffer.floatChannelData?[0] else { return nil }
    let count = Int(buffer.frameLength)
    guard count > 0 else { return nil }
    var sumSquares = 0.0
    for index in 0..<count {
        let value = Double(channel[index])
        sumSquares += value * value
    }
    let rms = sqrt(sumSquares / Double(count))
    let energyDBFS = 20 * log10(max(rms, 0.000_001))
    let pitch = estimatedPitch(channel: channel, count: count, sampleRate: buffer.format.sampleRate)
    return VocalSample(energyDBFS: energyDBFS, pitchHertz: pitch)
}

private func estimatedPitch(channel: UnsafeMutablePointer<Float>, count: Int, sampleRate: Double) -> Double? {
    guard count >= 512, sampleRate > 0 else { return nil }
    let minimumLag = max(1, Int(sampleRate / 300))
    let maximumLag = min(count / 2, Int(sampleRate / 80))
    guard minimumLag < maximumLag else { return nil }
    var bestLag = 0
    var bestCorrelation = 0.0
    for lag in stride(from: minimumLag, through: maximumLag, by: 2) {
        var correlation = 0.0
        var energy = 0.0
        for index in 0..<(count - lag) {
            let first = Double(channel[index])
            let second = Double(channel[index + lag])
            correlation += first * second
            energy += first * first
        }
        let normalized = energy > 0 ? correlation / energy : 0
        if normalized > bestCorrelation {
            bestCorrelation = normalized
            bestLag = lag
        }
    }
    guard bestLag > 0, bestCorrelation >= 0.35 else { return nil }
    return sampleRate / Double(bestLag)
}
