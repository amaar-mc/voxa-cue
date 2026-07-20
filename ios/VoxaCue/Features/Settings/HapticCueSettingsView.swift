import SwiftUI
import VoxaCore

struct HapticCueSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var advancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueTheme.Space.large) {
                cueGroup(title: "Essentials", cues: CueKind.essentialDefaults)
                cueGroup(title: "Presentation", cues: [.deckBehind])

                if !bandIsReady {
                    Label("Connect Cue Band to test signals", systemImage: "wave.3.right")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .padding(.horizontal, 4)
                }

                PremiumCard(padding: 20) {
                    DisclosureGroup(isExpanded: $advancedExpanded) {
                        VStack(spacing: 18) {
                            ForEach(CueKind.advanced, id: \.self) { cue in
                                cueEditor(cue)
                                if cue != CueKind.advanced.last {
                                    Divider().overlay(CueTheme.border)
                                }
                            }
                        }
                        .padding(.top, 18)
                    } label: {
                        Text("Advanced cues")
                            .font(.cueSection)
                            .foregroundStyle(CueTheme.ink)
                    }
                    .tint(CueTheme.signal)
                }

                Button("Restore cue defaults") {
                    model.restoreDefaultHaptics()
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CueTheme.signal)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, CueTheme.Space.large)
            .padding(.vertical, CueTheme.Space.medium)
        }
        .background(CueTheme.canvas)
        .navigationTitle("Haptic signals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cueGroup(title: String, cues: [CueKind]) -> some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.cueSection)
                    .foregroundStyle(CueTheme.ink)
                ForEach(cues, id: \.self) { cue in
                    cueEditor(cue)
                    if cue != cues.last {
                        Divider().overlay(CueTheme.border)
                    }
                }
            }
        }
    }

    private func cueEditor(_ cue: CueKind) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            cueEnablementHeader(cue)

            if cue == .fillerBurst {
                fillerClusterControls
            }

            patternMenu(for: cue)

            intensityPicker(for: cue)

            if bandIsReady {
                Button {
                    preview(cue)
                } label: {
                    Label("Test signal", systemImage: "wave.3.right")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.bordered)
                .tint(CueTheme.signal)
                .disabled(model.deviceLabCueDelivery.isPending)
            }
        }
    }

    @ViewBuilder
    private func cueEnablementHeader(_ cue: CueKind) -> some View {
        if cue == .deckBehind {
            HStack(spacing: 11) {
                cueIdentity(cue)
                Spacer(minLength: 8)
                Text("Choose per session")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
            }
        } else {
            Toggle(isOn: enabledBinding(cue)) {
                cueIdentity(cue)
            }
            .tint(CueTheme.signal)
        }
    }

    private func cueIdentity(_ cue: CueKind) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol(for: cue))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CueTheme.signal)
                .frame(width: 30, height: 30)
                .background(CueTheme.signalSoft)
                .clipShape(Circle())
            Text(cue.label)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CueTheme.ink)
        }
    }

    private func enabledBinding(_ cue: CueKind) -> Binding<Bool> {
        Binding(
            get: { model.hapticPreferences.enabledCues.contains(cue) },
            set: { model.setCueEnabled(cue, enabled: $0) }
        )
    }

    private func patternBinding(_ cue: CueKind) -> Binding<HapticPattern> {
        Binding(
            get: { model.hapticPreferences.patternByCue[cue] ?? .doubleTap },
            set: { model.setCuePattern(cue, pattern: $0) }
        )
    }

    private func patternMenu(for cue: CueKind) -> some View {
        let selectedPattern = model.hapticPreferences.patternByCue[cue] ?? .doubleTap

        return Menu {
            ForEach(HapticPattern.allCases, id: \.self) { pattern in
                Button {
                    model.setCuePattern(cue, pattern: pattern)
                } label: {
                    if pattern == selectedPattern {
                        Label(hapticPatternPulseDescription(pattern), systemImage: "checkmark")
                    } else {
                        Text(hapticPatternPulseDescription(pattern))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text("Pattern")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                Spacer(minLength: 12)
                Text(hapticPatternPulseDescription(selectedPattern))
                    .font(.cueCaption.weight(.semibold))
                    .foregroundStyle(CueTheme.signal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CueTheme.signal)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Pattern for \(cue.label)")
        .accessibilityValue(hapticPatternPulseDescription(selectedPattern))
    }

    private func intensityBinding(_ cue: CueKind) -> Binding<CueIntensity> {
        Binding(
            get: { model.hapticPreferences.intensityByCue[cue] ?? .medium },
            set: { model.setCueIntensity(cue, intensity: $0) }
        )
    }

    private var fillerRequiredCountBinding: Binding<Int> {
        Binding(
            get: { model.hapticPreferences.fillerClusterConfiguration.requiredFillerCount },
            set: { requiredFillerCount in
                let current = model.hapticPreferences.fillerClusterConfiguration
                model.setFillerClusterConfiguration(
                    FillerClusterConfiguration(
                        requiredFillerCount: requiredFillerCount,
                        windowSeconds: current.windowSeconds
                    )
                )
            }
        )
    }

    private var fillerWindowSecondsBinding: Binding<Int> {
        Binding(
            get: { model.hapticPreferences.fillerClusterConfiguration.windowSeconds },
            set: { windowSeconds in
                let current = model.hapticPreferences.fillerClusterConfiguration
                model.setFillerClusterConfiguration(
                    FillerClusterConfiguration(
                        requiredFillerCount: current.requiredFillerCount,
                        windowSeconds: windowSeconds
                    )
                )
            }
        )
    }

    private var fillerClusterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper(
                value: fillerRequiredCountBinding,
                in: FillerClusterConfiguration.requiredCountRange,
                step: 1
            ) {
                adjustmentLabel(
                    title: "Fillers required",
                    value: "\(model.hapticPreferences.fillerClusterConfiguration.requiredFillerCount)"
                )
            }
            .accessibilityLabel("Fillers required for a cluster")
            .accessibilityValue("\(model.hapticPreferences.fillerClusterConfiguration.requiredFillerCount)")

            Stepper(
                value: fillerWindowSecondsBinding,
                in: FillerClusterConfiguration.windowSecondsRange,
                step: FillerClusterConfiguration.windowStepSeconds
            ) {
                adjustmentLabel(
                    title: "Lookback window",
                    value: "\(model.hapticPreferences.fillerClusterConfiguration.windowSeconds) sec"
                )
            }
            .accessibilityLabel("Filler cluster lookback window")
            .accessibilityValue("\(model.hapticPreferences.fillerClusterConfiguration.windowSeconds) seconds")

            Text(fillerClusterDescription)
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func adjustmentLabel(title: String, value: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                Text(value)
                    .font(.cueCaption.monospacedDigit())
                    .foregroundStyle(CueTheme.ink)
            }
        } else {
            HStack(spacing: 12) {
                Text(title)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                Spacer(minLength: 8)
                Text(value)
                    .font(.cueCaption.monospacedDigit())
                    .foregroundStyle(CueTheme.ink)
            }
        }
    }

    private var fillerClusterDescription: String {
        "30-second cooldown. Lower count or longer window triggers sooner."
    }

    @ViewBuilder
    private func intensityPicker(for cue: CueKind) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 12) {
                Text("Strength")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                Spacer(minLength: 8)
                Picker("Strength for \(cue.label)", selection: intensityBinding(cue)) {
                    ForEach(CueIntensity.allCases, id: \.self) { intensity in
                        Text(intensity.label).tag(intensity)
                    }
                }
                .pickerStyle(.menu)
                .tint(CueTheme.signal)
            }
        } else {
            Picker("Strength for \(cue.label)", selection: intensityBinding(cue)) {
                ForEach(CueIntensity.allCases, id: \.self) { intensity in
                    Text(intensity.label).tag(intensity)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func preview(_ cue: CueKind) {
        model.sendDebugCue(
            pattern: model.hapticPreferences.patternByCue[cue] ?? .doubleTap,
            intensity: model.hapticPreferences.intensityByCue[cue] ?? .medium,
            repeatCount: 1
        )
    }

    private var bandIsReady: Bool {
        if case .ready = model.connectionState { return true }
        return false
    }

    private func symbol(for cue: CueKind) -> String {
        switch cue {
        case .tooFast: "hare"
        case .tooSlow: "tortoise"
        case .fillerBurst: "ellipsis.bubble"
        case .deckBehind: "rectangle.stack"
        case .time50, .time75, .time90, .time100: "timer"
        }
    }
}
