import SwiftUI
import VoxaCore

struct HapticCueSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var advancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueTheme.Space.large) {
                ScreenTitle(
                    eyebrow: "Cue language",
                    title: "Haptic signals",
                    subtitle: "Make every wrist cue recognizable without looking down."
                )

                cueGroup(title: "Essentials", cues: CueKind.essentialDefaults)

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
                        VStack(alignment: .leading, spacing: 3) {
                            CueSectionLabel(text: "Advanced cues", color: CueTheme.signal)
                            Text("Optional pace and timing reminders")
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.secondaryInk)
                        }
                    }
                    .tint(CueTheme.signal)
                }

                Button("Restore default signals") {
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
                CueSectionLabel(text: title, color: CueTheme.signal)
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
            Toggle(isOn: enabledBinding(cue)) {
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
            .tint(CueTheme.signal)

            HStack(spacing: 12) {
                Text("Pattern")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                Spacer(minLength: 8)
                Picker("Pattern for \(cue.label)", selection: patternBinding(cue)) {
                    ForEach(HapticPattern.allCases, id: \.self) { pattern in
                        Text(pattern.label).tag(pattern)
                    }
                }
                .pickerStyle(.menu)
                .tint(CueTheme.signal)
            }

            intensityPicker(for: cue)

            Button {
                preview(cue)
            } label: {
                Label("Test signal", systemImage: "wave.3.right")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.bordered)
            .tint(CueTheme.signal)
            .disabled(!bandIsReady || model.deviceLabCueDelivery.isPending)
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

    private func intensityBinding(_ cue: CueKind) -> Binding<CueIntensity> {
        Binding(
            get: { model.hapticPreferences.intensityByCue[cue] ?? .medium },
            set: { model.setCueIntensity(cue, intensity: $0) }
        )
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
