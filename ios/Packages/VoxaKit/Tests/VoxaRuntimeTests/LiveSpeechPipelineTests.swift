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
