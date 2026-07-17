import AVFoundation
import CoreMedia
import Foundation
import Speech
import Synchronization
import VoxaCore

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
    case builtInMicrophoneUnavailable
}

enum LiveAudioInputKind: Equatable, Sendable {
    case builtInMicrophone
    case other
}

func builtInMicrophoneRouteIsValid(inputKinds: [LiveAudioInputKind]) -> Bool {
    inputKinds == [.builtInMicrophone]
}

func liveAudioTapBufferSize(sampleRate: Double) throws -> AVAudioFrameCount {
    guard sampleRate.isFinite, sampleRate > 0 else {
        throw LiveSpeechPipelineError.invalidInputFormat
    }
    let frameCount = ceil(sampleRate * 0.1)
    guard frameCount <= Double(AVAudioFrameCount.max) else {
        throw LiveSpeechPipelineError.invalidInputFormat
    }
    return AVAudioFrameCount(frameCount)
}

struct ContiguousAnalyzerInputPlan {
    let buffer: AVAudioPCMBuffer
    let bufferStartTime: CMTime? = nil

    func makeInput() -> AnalyzerInput {
        AnalyzerInput(buffer: buffer, bufferStartTime: bufferStartTime)
    }
}

func contiguousAnalyzerInputPlan(buffer: AVAudioPCMBuffer) -> ContiguousAnalyzerInputPlan? {
    guard buffer.frameLength > 0 else { return nil }
    return ContiguousAnalyzerInputPlan(buffer: buffer)
}

func makeLiveAudioConverter(
    from inputFormat: AVAudioFormat,
    to outputFormat: AVAudioFormat
) -> AVAudioConverter? {
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
    converter.primeMethod = .none
    return converter
}

public enum LiveSpeechEvent: Sendable {
    case volatileTranscript(text: String, startSeconds: TimeInterval, endSeconds: TimeInterval)
    case finalizedTranscript(text: String, startSeconds: TimeInterval, endSeconds: TimeInterval)
    case voiceActivity(
        isSpeech: Bool,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval
    )
    case prosodySnapshot(ProsodySnapshot)
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
    private var interruptionTask: Task<Void, Never>?
    private var routeChangeTask: Task<Void, Never>?
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
        interruptionTask?.cancel()
        routeChangeTask?.cancel()
    }

    public nonisolated static func requestPermissions() async -> Bool {
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
            reportResults: false
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
                converter: makeLiveAudioConverter(from: naturalFormat, to: analyzerFormat),
                outputFormat: analyzerFormat
            )
            if naturalFormat != analyzerFormat, conversionContext.converter == nil {
                throw LiveSpeechPipelineError.conversionFailed
            }
            guard let prosodyFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: ProsodyConfiguration.voxaV1().pitch.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                throw LiveSpeechPipelineError.noCompatibleAudioFormat
            }
            let prosodyConversionContext = AudioConversionContext(
                converter: makeLiveAudioConverter(from: naturalFormat, to: prosodyFormat),
                outputFormat: prosodyFormat
            )
            if naturalFormat != prosodyFormat, prosodyConversionContext.converter == nil {
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

            let bufferPair = AsyncStream<SendableAudioBuffer>.makeStream(bufferingPolicy: .bufferingNewest(32))
            bufferContinuation = bufferPair.continuation
            let captureGate = self.captureGate
            bufferTask = Task.detached {
                var prosodyAnalyzer = ProsodyStreamAnalyzer(configuration: .voxaV1())
                var voiceActivityAnalyzer = VoiceActivityStreamAnalyzer(configuration: .voxaV1())
                for await item in bufferPair.stream {
                    guard captureGate.isActive(generation: item.captureGeneration) else { continue }
                    do {
                        let converted = try convert(
                            input: item.buffer,
                            converter: conversionContext.converter,
                            outputFormat: conversionContext.outputFormat
                        )
                        guard captureGate.isActive(generation: item.captureGeneration) else { continue }
                        if let inputPlan = contiguousAnalyzerInputPlan(buffer: converted) {
                            inputPair.continuation.yield(inputPlan.makeInput())
                        }
                        let prosodyBuffer = try convert(
                            input: item.buffer,
                            converter: prosodyConversionContext.converter,
                            outputFormat: prosodyConversionContext.outputFormat
                        )
                        if let samples = monoFloatSamples(prosodyBuffer) {
                            for frame in voiceActivityAnalyzer.consume(samples: samples) {
                                await eventHandler(
                                    .voiceActivity(
                                        isSpeech: frame.isSpeech,
                                        startSeconds: frame.startSeconds,
                                        endSeconds: frame.endSeconds
                                    )
                                )
                            }
                            for snapshot in prosodyAnalyzer.consume(samples: samples) {
                                await eventHandler(.prosodySnapshot(snapshot))
                            }
                        }
                    } catch {
                        await eventHandler(.failure(message: error.localizedDescription))
                    }
                }
                inputPair.continuation.finish()
            }

            captureGate.start()
            let tapHandler: AVAudioNodeTapBlock = { buffer, _ in
                guard let captureGeneration = captureGate.generationForCapture() else { return }
                guard let copy = copiedBuffer(buffer) else { return }
                bufferPair.continuation.yield(
                    SendableAudioBuffer(buffer: copy, captureGeneration: captureGeneration)
                )
            }
            let tapBufferSize = try liveAudioTapBufferSize(sampleRate: naturalFormat.sampleRate)
            if #available(iOS 27.0, macOS 27.0, *) {
                try audioEngine.inputNode.__installTap(
                    onBus: 0,
                    bufferSize: tapBufferSize,
                    format: naturalFormat,
                    error: (),
                    block: tapHandler
                )
            } else {
                audioEngine.inputNode.installTap(
                    onBus: 0,
                    bufferSize: tapBufferSize,
                    format: naturalFormat,
                    block: tapHandler
                )
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            #if os(iOS)
            observeAudioInterruptions()
            observeAudioRouteChanges()
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
        routeChangeTask?.cancel()
        routeChangeTask = nil
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
        clearRuntimeState()
        deactivateAudioSession()
    }

    private func rollbackFailedStart() async {
        captureGate.stop()
        interruptionTask?.cancel()
        interruptionTask = nil
        routeChangeTask?.cancel()
        routeChangeTask = nil
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
        interruptionTask = nil
        routeChangeTask = nil
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
        try session.setActive(true)
        guard let builtInMicrophone = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            throw LiveSpeechPipelineError.builtInMicrophoneUnavailable
        }
        try session.setPreferredInput(builtInMicrophone)
        try validateBuiltInMicrophoneRoute(session)
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

    private func observeAudioRouteChanges() {
        routeChangeTask?.cancel()
        routeChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                guard !Task.isCancelled else { return }
                do {
                    try self?.validateBuiltInMicrophoneRoute(AVAudioSession.sharedInstance())
                } catch {
                    self?.eventHandler?(
                        .failure(message: "The audio input changed. Voxa Cue requires the built-in iPhone microphone.")
                    )
                    return
                }
            }
        }
    }

    private func validateBuiltInMicrophoneRoute(_ session: AVAudioSession) throws {
        let inputKinds = session.currentRoute.inputs.map { input in
            input.portType == .builtInMic ? LiveAudioInputKind.builtInMicrophone : .other
        }
        guard builtInMicrophoneRouteIsValid(inputKinds: inputKinds) else {
            throw LiveSpeechPipelineError.builtInMicrophoneUnavailable
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
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio))
    guard capacity > 0 else { throw LiveSpeechPipelineError.conversionFailed }
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

private func monoFloatSamples(_ buffer: AVAudioPCMBuffer) -> [Float]? {
    guard let channel = buffer.floatChannelData?[0] else { return nil }
    let count = Int(buffer.frameLength)
    guard count > 0 else { return nil }
    return Array(UnsafeBufferPointer(start: channel, count: count))
}
