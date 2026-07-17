import AVFoundation
import Testing
@testable import VoxaRuntime

@Test("Live capture accepts only the built-in microphone route")
func liveCaptureRequiresBuiltInMicrophone() {
    #expect(builtInMicrophoneRouteIsValid(inputKinds: [.builtInMicrophone]))
    #expect(!builtInMicrophoneRouteIsValid(inputKinds: []))
    #expect(!builtInMicrophoneRouteIsValid(inputKinds: [.other]))
    #expect(!builtInMicrophoneRouteIsValid(inputKinds: [.builtInMicrophone, .other]))
}

@Test("Live audio tap requests Apple's minimum supported buffer duration")
func liveAudioTapUsesSupportedBufferDuration() throws {
    #expect(try liveAudioTapBufferSize(sampleRate: 48_000) == 4_800)
    #expect(try liveAudioTapBufferSize(sampleRate: 44_100) == 4_410)
    #expect(throws: LiveSpeechPipelineError.invalidInputFormat) {
        try liveAudioTapBufferSize(sampleRate: 0)
    }
}

@Test("Live analyzer inputs skip empty conversion output and use contiguous sequence timing")
func liveAnalyzerInputsCannotOverlap() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let emptyBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
    emptyBuffer.frameLength = 0
    #expect(contiguousAnalyzerInputPlan(buffer: emptyBuffer).map { _ in true } == nil)

    let audioBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3_748))
    audioBuffer.frameLength = 3_748
    let plan = try #require(contiguousAnalyzerInputPlan(buffer: audioBuffer))
    #expect(plan.bufferStartTime == nil)
}

@Test("Live sample-rate conversion disables priming timestamp drift")
func liveAudioConversionDisablesPriming() throws {
    let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let outputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let converter = try #require(makeLiveAudioConverter(from: inputFormat, to: outputFormat))

    #expect(converter.primeMethod == .none)
}
