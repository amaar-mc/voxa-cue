import Foundation
import Testing
import VoxaCore
@testable import VoxaRuntime

@Test("Session light UUID and active progress encode exactly")
func sessionLightEncodesExactly() throws {
    #expect(CueBLE.sessionLightUUID.uuidString == "6F2A0004-7C93-4A58-A9D4-3C52BBD1F110")
    let data = try CueBLE.encode(
        sessionLight: CueSessionLight(mode: .active, progressPercent: 42)
    )

    #expect([UInt8](data) == [1, 1, 42])
}

@Test("Session light rejects out-of-range progress")
func sessionLightRejectsInvalidProgress() {
    #expect(throws: CueBLEError.invalidSessionProgress) {
        try CueBLE.encode(
            sessionLight: CueSessionLight(mode: .active, progressPercent: 101)
        )
    }
}

@Test("Session timing maps to active, paused, overtime, and off light states")
func sessionTimingMapsToLightStates() {
    #expect(
        cueSessionLight(
            elapsedSeconds: 0,
            targetDurationSeconds: 120,
            presentationState: .active
        ) == CueSessionLight(mode: .active, progressPercent: 0)
    )
    #expect(
        cueSessionLight(
            elapsedSeconds: 60,
            targetDurationSeconds: 120,
            presentationState: .paused
        ) == CueSessionLight(mode: .paused, progressPercent: 50)
    )
    #expect(
        cueSessionLight(
            elapsedSeconds: 120,
            targetDurationSeconds: 120,
            presentationState: .active
        ) == CueSessionLight(mode: .active, progressPercent: 100)
    )
    #expect(
        cueSessionLight(
            elapsedSeconds: 120.01,
            targetDurationSeconds: 120,
            presentationState: .active
        ) == CueSessionLight(mode: .overtime, progressPercent: 100)
    )
    #expect(
        cueSessionLight(
            elapsedSeconds: 42,
            targetDurationSeconds: 120,
            presentationState: .off
        ) == CueSessionLight(mode: .off, progressPercent: 0)
    )
    #expect(
        cueSessionLight(
            elapsedSeconds: .nan,
            targetDurationSeconds: 120,
            presentationState: .active
        ) == CueSessionLight(mode: .off, progressPercent: 0)
    )
}

@Test("BLE discovery is service-based and recognizes diagnostic firmware")
func discoveryContractIncludesD2Diagnostic() {
    #expect(CueBLE.discoveryServiceUUIDs == [CueBLE.serviceUUID])
    #expect(CueBLE.knownPeripheralNames == ["Voxa Cue", "Voxa D2"])
}

@Test("BLE command matches the six-byte wire contract")
func commandEncodingMatchesContract() throws {
    let command = CueCommand(sequence: 0x1234, pattern: .calmWave, intensity: .strong, repeatCount: 2)
    let data = try CueBLE.encode(command: command)
    #expect([UInt8](data) == [1, 0x34, 0x12, HapticPattern.calmWave.rawValue, 2, 2])
}

@Test("Firmware 1.0 receives legacy equivalents for firmware 1.1 patterns")
func legacyFirmwarePatternCompatibility() {
    let calmWave = CueCommand(sequence: 8, pattern: .calmWave, intensity: .medium, repeatCount: 1)
    let deadline = CueCommand(sequence: 9, pattern: .deadlineHold, intensity: .strong, repeatCount: 1)

    #expect(CueBLE.command(calmWave, compatibleWithFirmwareMajor: 1, minor: 0).pattern == .tripleTap)
    #expect(CueBLE.command(deadline, compatibleWithFirmwareMajor: 1, minor: 0).pattern == .triplePulse)
    #expect(CueBLE.command(calmWave, compatibleWithFirmwareMajor: 1, minor: 1) == calmWave)
    #expect(CueBLE.command(deadline, compatibleWithFirmwareMajor: 2, minor: 0) == deadline)
}

@Test("BLE status decodes firmware and acknowledgement")
func statusDecodingMatchesContract() throws {
    let data = Data([1, 0x34, 0x12, 1, 0, 1, 4])
    let status = try CueBLE.decode(status: data)
    #expect(status.sequence == 0x1234)
    #expect(status.state == .completed)
    #expect(status.error == .none)
    #expect(status.firmwareMajor == 1)
    #expect(status.firmwareMinor == 4)
}

@Test("BLE status decodes accepted and driver-fault acknowledgements")
func statusDecodingCoversCommandLifecycle() throws {
    let accepted = try CueBLE.decode(status: Data([1, 7, 0, 0, 0, 1, 0]))
    let rejected = try CueBLE.decode(status: Data([1, 8, 0, 2, 3, 1, 0]))

    #expect(accepted.sequence == 7)
    #expect(accepted.state == .accepted)
    #expect(accepted.error == .none)
    #expect(rejected.sequence == 8)
    #expect(rejected.state == .rejected)
    #expect(rejected.error == .driverFault)
}

@Test("BLE acknowledgement lifecycle requires acceptance and rejects status errors")
func acknowledgementLifecycleFailsClosed() {
    let accepted = CueBandStatus(
        sequence: 12,
        state: .accepted,
        error: .none,
        firmwareMajor: 1,
        firmwareMinor: 0
    )
    let completed = CueBandStatus(
        sequence: 12,
        state: .completed,
        error: .none,
        firmwareMajor: 1,
        firmwareMinor: 0
    )
    let malformedCompletion = CueBandStatus(
        sequence: 12,
        state: .completed,
        error: .driverFault,
        firmwareMajor: 1,
        firmwareMinor: 0
    )

    #expect(
        advanceCueBandAcknowledgement(.awaitingAcceptance, with: completed)
            == .failed(.completionBeforeAcceptance)
    )
    let awaitingCompletion = advanceCueBandAcknowledgement(.awaitingAcceptance, with: accepted)
    #expect(awaitingCompletion == .awaitingCompletion)
    #expect(advanceCueBandAcknowledgement(awaitingCompletion, with: completed) == .completed)
    #expect(
        advanceCueBandAcknowledgement(.awaitingCompletion, with: malformedCompletion)
            == .failed(.statusError(.driverFault))
    )
}

@Test("BLE decoder rejects incompatible protocol")
func incompatibleProtocolIsRejected() {
    #expect(throws: CueBLEError.incompatibleProtocol(2)) {
        try CueBLE.decode(status: Data([2, 0, 0, 0, 0, 1, 0]))
    }
}
