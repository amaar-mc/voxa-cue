@preconcurrency import CoreBluetooth
import Foundation
import VoxaCore

@MainActor
public final class CueBandClient: NSObject {
    public typealias StateHandler = @MainActor @Sendable (CueBandConnectionState) -> Void
    public typealias StatusHandler = @MainActor @Sendable (CueBandStatus) -> Void

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var shouldReconnect = false
    private var failedPeripheralID: UUID?
    private var stateHandler: StateHandler?
    private var statusHandler: StatusHandler?

    public override init() {
        super.init()
    }

    public func connect(stateHandler: @escaping StateHandler, statusHandler: @escaping StatusHandler) {
        self.stateHandler = stateHandler
        self.statusHandler = statusHandler
        shouldReconnect = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            beginScan()
        }
    }

    public func disconnect() {
        shouldReconnect = false
        failedPeripheralID = nil
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        resetConnection()
        stateHandler?(.idle)
    }

    public func send(command: CueCommand) throws {
        guard let peripheral,
              peripheral.state == .connected,
              let commandCharacteristic else {
            throw CueBLEError.notConnected
        }
        peripheral.writeValue(try CueBLE.encode(command: command), for: commandCharacteristic, type: .withResponse)
    }

    private func beginScan() {
        guard let central else { return }
        guard central.state == .poweredOn else {
            stateHandler?(.bluetoothUnavailable)
            return
        }
        stateHandler?(.searching)
        central.scanForPeripherals(withServices: [CueBLE.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func resetConnection() {
        peripheral?.delegate = nil
        peripheral = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
    }

    private func failConnection(_ message: String) {
        shouldReconnect = false
        central?.stopScan()
        if let peripheral {
            failedPeripheralID = peripheral.identifier
            central?.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
        stateHandler?(.failed(message))
    }
}

extension CueBandClient: @MainActor CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScan()
        case .poweredOff, .unauthorized, .unsupported:
            resetConnection()
            stateHandler?(.bluetoothUnavailable)
        case .resetting, .unknown:
            stateHandler?(.reconnecting)
        @unknown default:
            stateHandler?(.failed("Unknown Bluetooth state"))
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        stateHandler?(.connecting)
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        stateHandler?(.discovering)
        peripheral.discoverServices([CueBLE.serviceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        resetConnection()
        stateHandler?(.failed(error?.localizedDescription ?? "Cue did not accept the connection"))
        if shouldReconnect { beginScan() }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        if failedPeripheralID == peripheral.identifier {
            failedPeripheralID = nil
            return
        }
        resetConnection()
        guard shouldReconnect else {
            stateHandler?(.idle)
            return
        }
        stateHandler?(.reconnecting)
        beginScan()
    }
}

extension CueBandClient: @MainActor CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            failConnection(error.localizedDescription)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == CueBLE.serviceUUID }) else {
            failConnection("Cue service is unavailable")
            return
        }
        peripheral.discoverCharacteristics([CueBLE.commandUUID, CueBLE.statusUUID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        if let error {
            failConnection(error.localizedDescription)
            return
        }
        commandCharacteristic = service.characteristics?.first(where: { $0.uuid == CueBLE.commandUUID })
        statusCharacteristic = service.characteristics?.first(where: { $0.uuid == CueBLE.statusUUID })
        guard let commandCharacteristic,
              commandCharacteristic.properties.contains(.write),
              let statusCharacteristic,
              statusCharacteristic.properties.contains(.read),
              statusCharacteristic.properties.contains(.notify) else {
            failConnection("Cue firmware is incompatible")
            return
        }
        peripheral.setNotifyValue(true, for: statusCharacteristic)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard characteristic.uuid == CueBLE.statusUUID else { return }
        if let error {
            failConnection(error.localizedDescription)
            return
        }
        guard characteristic.isNotifying else {
            failConnection("Cue status notifications are unavailable")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard characteristic.uuid == CueBLE.statusUUID else { return }
        if let error {
            failConnection(error.localizedDescription)
            return
        }
        guard let value = characteristic.value else {
            failConnection("Cue returned an empty status packet")
            return
        }
        let status: CueBandStatus
        do {
            status = try CueBLE.decode(status: value)
        } catch {
            failConnection("Cue returned an incompatible status packet")
            return
        }
        stateHandler?(.ready(firmware: "\(status.firmwareMajor).\(status.firmwareMinor)"))
        statusHandler?(status)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error { failConnection(error.localizedDescription) }
    }
}
