import SwiftUI
import VoxaCore
import VoxaRuntime

struct DeviceLabView: View {
    @Environment(AppModel.self) private var model
    @State private var cueKind = CueKind.tooFast
    @State private var intensity = CueIntensity.soft
    @State private var repeatCount = 1

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("State", value: model.connectionState.label)
                if case let .failed(message) = model.connectionState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if case let .ready(firmware) = model.connectionState {
                    LabeledContent("Firmware", value: firmware)
                }
                if let band = model.discoveredBand {
                    LabeledContent("Name", value: band.name)
                    LabeledContent("Identifier", value: band.identifier.uuidString)
                    LabeledContent("Signal", value: "\(band.rssi) dBm")
                }
                Button("Scan and connect") {
                    model.connectCueBand()
                }
                .disabled(connectionIsBusy || bandIsReady)

                Button("Disconnect", role: .destructive) {
                    model.disconnectCueBand()
                }
                .disabled(!connectionIsActive)

                Text("Connects to the first nearby device advertising the Voxa Cue BLE v1 service. No Bluetooth Settings pairing is required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Test command") {
                Picker("Pattern", selection: $cueKind) {
                    ForEach(CueKind.liveMVP, id: \.self) { cue in
                        Text(cue.label).tag(cue)
                    }
                }
                Picker("Intensity", selection: $intensity) {
                    ForEach(CueIntensity.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                Stepper("Repeat count: \(repeatCount)", value: $repeatCount, in: 1...3)
                Button("Send haptic command") {
                    model.sendDebugCue(
                        kind: cueKind,
                        intensity: intensity,
                        repeatCount: UInt8(repeatCount)
                    )
                }
                .disabled(!bandIsReady)
            }

            Section("Last status") {
                if let status = model.lastBandStatus {
                    LabeledContent("Sequence", value: String(status.sequence))
                    LabeledContent("State", value: statusLabel(status.state))
                    LabeledContent("Error", value: errorLabel(status.error))
                } else {
                    Text("No status packet received")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Packet trace") {
                packetRow(label: "Write requested", data: model.lastWriteRequestPacket)
                packetRow(label: "Received", data: model.lastReceivedBandPacket)
            }

            Section("Expected firmware") {
                LabeledContent("Board", value: "Arduino Nano 33 IoT")
                LabeledContent("Protocol", value: "BLE v\(CueBLE.protocolVersion)")
                LabeledContent("Device name", value: "Voxa Cue")
                Text(CueBLE.serviceUUID.uuidString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Device Lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func packetRow(label: String, data: Data?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Text(hexString(data))
                .font(.caption.monospaced())
                .foregroundStyle(data == nil ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    private var bandIsReady: Bool {
        if case .ready = model.connectionState { return true }
        return false
    }

    private var connectionIsBusy: Bool {
        switch model.connectionState {
        case .searching, .connecting, .discovering, .reconnecting: true
        default: false
        }
    }

    private var connectionIsActive: Bool {
        switch model.connectionState {
        case .idle, .bluetoothUnavailable: false
        default: true
        }
    }

    private func hexString(_ data: Data?) -> String {
        guard let data else { return "—" }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func statusLabel(_ state: CueBandCommandState) -> String {
        switch state {
        case .accepted: "Accepted"
        case .completed: "Completed"
        case .rejected: "Rejected"
        }
    }

    private func errorLabel(_ error: CueBandCommandError) -> String {
        switch error {
        case .none: "None"
        case .invalidVersion: "Invalid protocol version"
        case .invalidCommand: "Invalid command"
        case .driverFault: "Haptic driver fault"
        }
    }
}
