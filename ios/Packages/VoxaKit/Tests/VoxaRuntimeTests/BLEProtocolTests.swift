import Foundation
import Testing
import VoxaCore
@testable import VoxaRuntime

@Test("BLE command matches the six-byte wire contract")
func commandEncodingMatchesContract() throws {
    let command = CueCommand(sequence: 0x1234, kind: .fillerBurst, intensity: .strong, repeatCount: 2)
    let data = try CueBLE.encode(command: command)
    #expect([UInt8](data) == [1, 0x34, 0x12, 3, 2, 2])
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

@Test("BLE decoder rejects incompatible protocol")
func incompatibleProtocolIsRejected() {
    #expect(throws: CueBLEError.incompatibleProtocol(2)) {
        try CueBLE.decode(status: Data([2, 0, 0, 0, 0, 1, 0]))
    }
}
