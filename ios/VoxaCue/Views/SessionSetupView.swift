import SwiftUI
import VoxaCore

struct SessionSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Practice Session"
    @State private var targetMinutes = 5.0
    @State private var minimumWPM = 130.0
    @State private var maximumWPM = 160.0
    @State private var intensity = CueIntensity.medium
    @State private var enabledCues = Set(CueKind.liveMVP)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(
                        eyebrow: "New session",
                        title: "Set your coaching target",
                        subtitle: "Cue listens through this iPhone and coaches pace, fillers, and timing."
                    )
                    basicsCard
                    paceCard
                    cueCard
                    preflightCard
                    VStack(alignment: .leading, spacing: 9) {
                        VoxaButton(
                            title: beginButtonTitle,
                            symbol: "arrow.up.right",
                            style: .primary,
                            disabled: startDisabled,
                            action: begin
                        )
                        if let startDisabledReason {
                            Label(startDisabledReason, systemImage: "info.circle")
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.secondaryInk)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
            .background(CueTheme.canvas)
            .navigationTitle("Session setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var basicsCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                CueSectionLabel(text: "Session", color: CueTheme.signal)
                TextField("Session name", text: $name)
                    .font(.cueBody)
                    .padding(15)
                    .background(CueTheme.canvas.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.small, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CueTheme.Radius.small, style: .continuous)
                            .stroke(CueTheme.border, lineWidth: 0.75)
                    }
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)

                Stepper(value: $targetMinutes, in: 1...30, step: 1) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Target duration")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(CueTheme.ink)
                            Text("Drives private timing reminders")
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Text("\(Int(targetMinutes)) min")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(CueTheme.signal)
                    }
                }
            }
        }
    }

    private var paceCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    CueSectionLabel(text: "Pace range", color: CueTheme.signal)
                    Spacer(minLength: 8)
                    Text("\(Int(minimumWPM))–\(Int(maximumWPM)) WPM")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(paceRangeIsValid ? CueTheme.ink : CueTheme.red)
                }
                VStack(spacing: 15) {
                    labeledSlider(label: "Minimum", value: $minimumWPM, range: 90...150)
                    labeledSlider(label: "Maximum", value: $maximumWPM, range: 140...210)
                }
                Text(
                    paceRangeIsValid
                        ? "A rolling window prevents one rushed sentence from triggering a cue."
                        : "Maximum pace must be higher than minimum pace."
                )
                .font(.cueCaption)
                .foregroundStyle(paceRangeIsValid ? CueTheme.secondaryInk : CueTheme.red)
            }
        }
    }

    private func labeledSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                Spacer()
                Text("\(Int(value.wrappedValue)) WPM")
                    .font(.cueCaption.monospacedDigit())
                    .foregroundStyle(CueTheme.ink)
            }
            Slider(value: value, in: range, step: 5)
                .tint(CueTheme.signal)
                .accessibilityLabel("\(label) speaking pace")
                .accessibilityValue("\(Int(value.wrappedValue)) words per minute")
        }
    }

    private var cueCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        CueSectionLabel(text: "Haptic cues", color: CueTheme.signal)
                        Spacer(minLength: 8)
                        intensityPicker
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        CueSectionLabel(text: "Haptic cues", color: CueTheme.signal)
                        intensityPicker
                    }
                }
                ForEach(CueKind.liveMVP, id: \.self) { cue in
                    Toggle(isOn: cueBinding(cue)) {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: cue))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(CueTheme.signal)
                                .frame(width: 32, height: 32)
                                .background(CueTheme.signalSoft)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cue.label)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(CueTheme.ink)
                                Text(patternDescription(for: cue))
                                    .font(.cueCaption)
                                    .foregroundStyle(CueTheme.secondaryInk)
                            }
                        }
                    }
                    .tint(CueTheme.signal)
                }
                if enabledCues.isEmpty {
                    Label("Analytics will continue without wrist cues.", systemImage: "chart.xyaxis.line")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                }
            }
        }
    }

    private var intensityPicker: some View {
        HStack(spacing: 8) {
            Text("Intensity")
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
            Picker("Haptic intensity", selection: $intensity) {
                ForEach(CueIntensity.allCases, id: \.self) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var preflightCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                CueSectionLabel(text: "Preflight", color: CueTheme.signal)
                preflightRow(
                    label: model.demoMode ? "Audio source" : "Phone microphone",
                    detail: model.demoMode ? "Deterministic simulation" : "Permission checked when you begin",
                    state: model.demoMode ? .ready : .pending
                )
                preflightRow(label: "Cue Band", detail: bandPreflightDetail, state: bandPreflightState)
                if !isCueReady {
                    Button {
                        model.connectCueBand()
                    } label: {
                        Label("Connect Cue Band", systemImage: "wave.3.right")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(CueTheme.signal)
                    .disabled(bandConnectionIsBusy)
                }
            }
        }
    }

    private func preflightRow(label: String, detail: String, state: PreflightState) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: state.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CueTheme.ink)
                Text(detail)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var isCueReady: Bool {
        if case .ready = model.connectionState { return true }
        return false
    }

    private var bandConnectionIsBusy: Bool {
        switch model.connectionState {
        case .searching, .connecting, .discovering, .reconnecting: true
        default: false
        }
    }

    private var bandPreflightState: PreflightState {
        if isCueReady { return enabledCues.isEmpty ? .optional : .ready }
        if bandConnectionIsBusy { return .pending }
        return .optional
    }

    private var bandPreflightDetail: String {
        if isCueReady, enabledCues.isEmpty { return "Connected · all wrist cues are off" }
        if isCueReady { return "Connected for live haptics" }
        if bandConnectionIsBusy { return model.connectionState.label }
        return "Optional · analytics continue without it"
    }

    private var paceRangeIsValid: Bool {
        minimumWPM < maximumWPM
    }

    private var willSendHaptics: Bool {
        isCueReady && !enabledCues.isEmpty
    }

    private var beginButtonTitle: String {
        willSendHaptics ? "Begin with haptics" : "Begin analytics only"
    }

    private var startDisabled: Bool {
        startDisabledReason != nil
    }

    private var startDisabledReason: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a session name to continue."
        }
        if !paceRangeIsValid {
            return "Set a valid pace range to continue."
        }
        return nil
    }

    private func cueBinding(_ cue: CueKind) -> Binding<Bool> {
        Binding(
            get: { enabledCues.contains(cue) },
            set: { enabled in
                if enabled { enabledCues.insert(cue) } else { enabledCues.remove(cue) }
            }
        )
    }

    private func symbol(for cue: CueKind) -> String {
        switch cue {
        case .tooFast: "hare"
        case .tooSlow: "tortoise"
        case .fillerBurst: "ellipsis.bubble"
        case .deckBehind: "rectangle.stack.badge.play"
        case .time75, .time90, .time100: "timer"
        }
    }

    private func patternDescription(for cue: CueKind) -> String {
        switch cue {
        case .tooFast: "Two short pulses · ease your pace"
        case .tooSlow: "One long pulse · add energy"
        case .fillerBurst: "Three short pulses · reset with a pause"
        case .deckBehind: "Reserved for a future presentation mode"
        case .time75: "One pronounced pulse · 75% elapsed"
        case .time90: "Two pronounced pulses · 90% elapsed"
        case .time100: "Three pronounced pulses · target reached"
        }
    }

    private func begin() {
        let intensityMap = Dictionary(uniqueKeysWithValues: CueKind.liveMVP.map { ($0, intensity) })
        let baseProfile = CoachingProfile.rehearsalV1()
        let profile = CoachingProfile(
            minimumWPM: minimumWPM,
            maximumWPM: maximumWPM,
            enabledCues: enabledCues,
            intensityByCue: intensityMap,
            highConfidenceFillers: baseProfile.highConfidenceFillers,
            optionalFillers: baseProfile.optionalFillers
        )
        let configuration = SessionConfiguration(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: .freeSpeaking,
            targetDurationSeconds: targetMinutes * 60,
            profile: profile,
            deckPlan: nil
        )
        model.beginSession(configuration: configuration)
    }
}

private enum PreflightState {
    case ready
    case pending
    case optional

    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .optional: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: CueTheme.green
        case .pending: CueTheme.signal
        case .optional: CueTheme.secondaryInk
        }
    }
}
