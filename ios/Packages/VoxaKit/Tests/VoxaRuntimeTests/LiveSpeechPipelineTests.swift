import Testing
@testable import VoxaRuntime

@Test("Live capture accepts only the built-in microphone route")
func liveCaptureRequiresBuiltInMicrophone() {
    #expect(builtInMicrophoneRouteIsValid(inputKinds: [.builtInMicrophone]))
    #expect(!builtInMicrophoneRouteIsValid(inputKinds: []))
    #expect(!builtInMicrophoneRouteIsValid(inputKinds: [.other]))
    #expect(!builtInMicrophoneRouteIsValid(inputKinds: [.builtInMicrophone, .other]))
}
