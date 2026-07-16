@preconcurrency import CoreBluetooth
import Foundation
import VoxaCore

public enum CueBLE {
    public static let protocolVersion: UInt8 = 1
    public static let serviceUUID = CBUUID(string: "6F2A0001-7C93-4A58-A9D4-3C52BBD1F110")
    public static let commandUUID = CBUUID(string: "6F2A0002-7C93-4A58-A9D4-3C52BBD1F110")
    public static let statusUUID = CBUUID(string: "6F2A0003-7C93-4A58-A9D4-3C52BBD1F110")

    public static func encode(command: CueCommand) throws -> Data {
        guard (1...3).contains(command.repeatCount) else { throw CueBLEError.invalidRepeatCount }
        return Data([
            protocolVersion,
            UInt8(truncatingIfNeeded: command.sequence),
            UInt8(truncatingIfNeeded: command.sequence >> 8),
            command.kind.rawValue,
            command.intensity.rawValue,
            command.repeatCount
        ])
    }

    public static func decode(status data: Data) throws -> CueBandStatus {
        guard data.count == 7 else { throw CueBLEError.invalidPacketLength }
        let bytes = [UInt8](data)
        guard bytes[0] == protocolVersion else { throw CueBLEError.incompatibleProtocol(bytes[0]) }
        guard let state = CueBandCommandState(rawValue: bytes[3]),
              let error = CueBandCommandError(rawValue: bytes[4]) else {
            throw CueBLEError.invalidStatus
        }
        let sequence = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        return CueBandStatus(
            sequence: sequence,
            state: state,
            error: error,
            firmwareMajor: bytes[5],
            firmwareMinor: bytes[6]
        )
    }
}

public enum CueBLEError: Error, Equatable {
    case invalidRepeatCount
    case invalidPacketLength
    case incompatibleProtocol(UInt8)
    case invalidStatus
    case notConnected
}

public enum CueBandCommandState: UInt8, Codable, Sendable {
    case accepted = 0
    case completed = 1
    case rejected = 2
}

public enum CueBandCommandError: UInt8, Codable, Sendable {
    case none = 0
    case invalidVersion = 1
    case invalidCommand = 2
    case driverFault = 3
}

public enum CueBandPacketDirection: Equatable, Sendable {
    case writeRequested
    case received
}

public struct CueBandPacket: Equatable, Sendable {
    public let direction: CueBandPacketDirection
    public let data: Data

    public init(direction: CueBandPacketDirection, data: Data) {
        self.direction = direction
        self.data = data
    }
}

public struct CueBandStatus: Equatable, Sendable {
    public let sequence: UInt16
    public let state: CueBandCommandState
    public let error: CueBandCommandError
    public let firmwareMajor: UInt8
    public let firmwareMinor: UInt8

    public init(
        sequence: UInt16,
        state: CueBandCommandState,
        error: CueBandCommandError,
        firmwareMajor: UInt8,
        firmwareMinor: UInt8
    ) {
        self.sequence = sequence
        self.state = state
        self.error = error
        self.firmwareMajor = firmwareMajor
        self.firmwareMinor = firmwareMinor
    }
}

public enum CueBandConnectionState: Equatable, Sendable {
    case idle
    case bluetoothUnavailable
    case searching
    case connecting
    case discovering
    case ready(firmware: String)
    case reconnecting
    case failed(String)

    public var label: String {
        switch self {
        case .idle: "Not connected"
        case .bluetoothUnavailable: "Bluetooth is off"
        case .searching: "Searching for Cue"
        case .connecting: "Connecting"
        case .discovering: "Finishing connection"
        case .ready: "Connected"
        case .reconnecting: "Reconnecting"
        case .failed: "Connection failed"
        }
    }
}
