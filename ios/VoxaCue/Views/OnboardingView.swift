import SwiftUI
import VoxaCore

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let presentation: OnboardingPresentation
    @State private var page = OnboardingStep.welcome.rawValue

    var body: some View {
        ZStack {
            CueTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(OnboardingStep.allCases) { step in
                        OnboardingStepView(step: step, presentation: presentation)
                            .tag(step.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(CueMotion.settle(reduceMotion: reduceMotion), value: page)
                footer
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CueWordmark(compact: dynamicTypeSize.isAccessibilitySize)
            Spacer(minLength: 8)
            Text("\(page + 1) of \(OnboardingStep.allCases.count)")
                .font(.cueCaption.monospacedDigit())
                .foregroundStyle(CueTheme.secondaryInk)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Setup page \(page + 1) of \(OnboardingStep.allCases.count)")
            Button(action: model.skipOnboarding) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CueTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(CueTheme.surface)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(CueTheme.border, lineWidth: 0.7)
                    }
            }
            .buttonStyle(SpringPressStyle())
            .accessibilityLabel(presentation == .firstRun ? "Skip setup" : "Close setup guide")
            .accessibilityHint("Returns to the Voxa Cue app")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases) { step in
                    Capsule()
                        .fill(step.rawValue == page ? CueTheme.signal : CueTheme.border)
                        .frame(width: step.rawValue == page ? 25 : 7, height: 7)
                        .animation(CueMotion.quick(reduceMotion: reduceMotion), value: page)
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 12) {
                if page > OnboardingStep.welcome.rawValue {
                    Button(action: moveBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CueTheme.signal)
                            .frame(width: 56, height: 56)
                            .background(CueTheme.signalSoft)
                            .clipShape(Circle())
                    }
                    .buttonStyle(SpringPressStyle())
                    .accessibilityLabel("Previous setup page")
                }

                VoxaButton(
                    title: dynamicTypeSize.isAccessibilitySize
                        ? currentStep.compactPrimaryActionTitle
                        : currentStep.primaryActionTitle,
                    symbol: currentStep.primaryActionSymbol,
                    style: .primary,
                    disabled: false,
                    action: advance
                )
            }

            if currentStep == .ready {
                Button(alternateCompletionTitle) {
                    model.completeOnboarding(openSessionSetup: false)
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CueTheme.secondaryInk)
                .frame(minHeight: 44)
                .buttonStyle(SpringPressStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(CueTheme.canvas)
    }

    private var currentStep: OnboardingStep {
        OnboardingStep(rawValue: page) ?? .welcome
    }

    private var alternateCompletionTitle: String {
        presentation == .firstRun ? "Explore the app first" : "Return to Settings"
    }

    private func moveBack() {
        guard page > OnboardingStep.welcome.rawValue else { return }
        withAnimation(CueMotion.settle(reduceMotion: reduceMotion)) {
            page -= 1
        }
    }

    private func advance() {
        if currentStep == .ready {
            model.completeOnboarding(openSessionSetup: true)
            return
        }
        withAnimation(CueMotion.settle(reduceMotion: reduceMotion)) {
            page += 1
        }
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case cues
    case band
    case ready

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .welcome: "Meet Voxa Cue"
        case .cues: "Ready from day one"
        case .band: "Optional wrist feedback"
        case .ready: "Your first rehearsal"
        }
    }

    var title: String {
        switch self {
        case .welcome: "Your voice, coached in the moment."
        case .cues: "Four cues. One clear language."
        case .band: "Pair your Cue Band."
        case .ready: "Start with a simple target."
        }
    }

    func body(presentation: OnboardingPresentation) -> String {
        switch self {
        case .welcome:
            "Set a goal, place your iPhone nearby, and speak. Cue tracks pace, fillers, and time while you present."
        case .cues:
            presentation == .firstRun
                ? "These recommended signals are already active. You can tune every pulse later."
                : "This is the recommended starting set. Your custom cue settings will stay unchanged."
        case .band:
            "Power on the band and keep it nearby. You can also continue with phone-only analytics."
        case .ready:
            "Your first setup opens at five minutes and 130–160 words per minute. Adjust either before you begin."
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .welcome: "Show my starter cues"
        case .cues: "Connect my band"
        case .band: "Prepare my rehearsal"
        case .ready: "Set up first session"
        }
    }

    var compactPrimaryActionTitle: String {
        switch self {
        case .welcome, .cues, .band: "Next"
        case .ready: "Set up"
        }
    }

    var primaryActionSymbol: String {
        switch self {
        case .welcome, .cues, .band: "chevron.right"
        case .ready: "arrow.up.right"
        }
    }
}

private struct OnboardingStepView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let step: OnboardingStep
    let presentation: OnboardingPresentation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 10 : 26)
                CueSectionLabel(text: step.eyebrow, color: CueTheme.signal)
                Text(step.title)
                    .font(.cueHero)
                    .foregroundStyle(CueTheme.ink)
                    .lineSpacing(-1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(step.body(presentation: presentation))
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                stepDetail
                Spacer(minLength: 14)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var stepDetail: some View {
        switch step {
        case .welcome:
            welcomeCard
        case .cues:
            starterCueCard
        case .band:
            bandCard
        case .ready:
            rehearsalCard
        }
    }

    private var welcomeCard: some View {
        HeroCard(padding: 20) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionMark(assetName: "VoiceSignal", size: 104)
                        welcomeFeatures
                    }
                } else {
                    HStack(spacing: 20) {
                        SectionMark(assetName: "VoiceSignal", size: 112)
                        welcomeFeatures
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var welcomeFeatures: some View {
        VStack(alignment: .leading, spacing: 13) {
            compactFeature(symbol: "iphone", title: "Phone microphone")
            compactFeature(symbol: "waveform", title: "Live analysis")
            compactFeature(symbol: "applewatch.radiowaves.left.and.right", title: "Private haptics")
        }
    }

    private var starterCueCard: some View {
        let defaults = HapticPreferences.defaultsV1()
        return PremiumCard(padding: 18) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(CueKind.essentialDefaults.enumerated()), id: \.element) { index, cue in
                    starterCueRow(cue: cue, defaults: defaults)
                    if index < CueKind.essentialDefaults.count - 1 {
                        Divider()
                            .overlay(CueTheme.border)
                            .padding(.leading, 44)
                    }
                }
                StatusPill(
                    label: starterPresetStatus,
                    symbol: model.hapticPreferences == defaults ? "checkmark.circle.fill" : "slider.horizontal.3",
                    color: model.hapticPreferences == defaults ? CueTheme.green : CueTheme.signal
                )
                .padding(.top, 14)
            }
        }
    }

    private var bandCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 15) {
                    SectionMark(assetName: "HapticBand", size: 72)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Cue Band")
                            .font(.cueSection)
                            .foregroundStyle(CueTheme.ink)
                        StatusPill(
                            label: model.connectionState.label,
                            symbol: bandStatusSymbol,
                            color: bandStatusColor
                        )
                    }
                }
                if bandIsReady {
                    Label("Ready for private wrist cues", systemImage: "checkmark.circle.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(CueTheme.green)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                } else {
                    VoxaButton(
                        title: bandIsBusy ? "Searching for Cue Band…" : "Connect Cue Band",
                        symbol: "dot.radiowaves.left.and.right",
                        style: .secondary,
                        disabled: bandIsBusy,
                        action: model.connectCueBand
                    )
                }
            }
        }
    }

    private var rehearsalCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 15) {
                    SectionMark(assetName: "OnDevicePrivacy", size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        CueSectionLabel(text: "Recommended start", color: CueTheme.signal)
                        Text("A focused five-minute run")
                            .font(.cueSection)
                            .foregroundStyle(CueTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().overlay(CueTheme.border)
                readinessRow(symbol: "timer", label: "Target", value: "5 minutes")
                readinessRow(symbol: "waveform.path.ecg", label: "Pace", value: "130–160 WPM")
                readinessRow(symbol: "mic.fill", label: "Audio", value: "This iPhone")
                Label("Microphone access is requested only when you begin. Raw audio is never saved.", systemImage: "lock.shield.fill")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private var starterPresetStatus: String {
        model.hapticPreferences == .defaultsV1()
            ? "Recommended preset active"
            : "Your custom cues are preserved"
    }

    private func compactFeature(symbol: String, title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(CueTheme.ink)
    }

    private func starterCueRow(cue: CueKind, defaults: HapticPreferences) -> some View {
        HStack(spacing: 12) {
            Image(systemName: cueSymbol(cue))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CueTheme.signal)
                .frame(width: 32, height: 32)
                .background(CueTheme.signalSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(cue.label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CueTheme.ink)
                Text(starterCueDetail(cue: cue, defaults: defaults))
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func starterCueDetail(cue: CueKind, defaults: HapticPreferences) -> String {
        let pattern = defaults.patternByCue[cue]?.label ?? "Recommended signal"
        if cue == .fillerBurst {
            let configuration = defaults.fillerClusterConfiguration
            return "\(pattern) · \(configuration.requiredFillerCount) fillers in \(configuration.windowSeconds) sec"
        }
        let intensity = defaults.intensityByCue[cue]?.label ?? "Medium"
        return "\(pattern) · \(intensity)"
    }

    private func cueSymbol(_ cue: CueKind) -> String {
        switch cue {
        case .tooFast: "speedometer"
        case .fillerBurst: "quote.bubble"
        case .time50: "circle.lefthalf.filled"
        case .time100: "timer"
        case .tooSlow: "forward.fill"
        case .time75, .time90: "clock"
        case .deckBehind: "rectangle.stack.badge.play"
        }
    }

    private func readinessRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CueTheme.signal)
                .frame(width: 30, height: 30)
                .background(CueTheme.signalSoft)
                .clipShape(Circle())
            Text(label)
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var bandIsReady: Bool {
        if case .ready = model.connectionState { return true }
        return false
    }

    private var bandIsBusy: Bool {
        switch model.connectionState {
        case .searching, .connecting, .discovering, .reconnecting: true
        case .idle, .bluetoothUnavailable, .ready, .failed: false
        }
    }

    private var bandStatusSymbol: String {
        if bandIsReady { return "checkmark.circle.fill" }
        if bandIsBusy { return "antenna.radiowaves.left.and.right" }
        if case .failed = model.connectionState { return "exclamationmark.triangle.fill" }
        return "applewatch"
    }

    private var bandStatusColor: Color {
        if bandIsReady { return CueTheme.green }
        if bandIsBusy { return CueTheme.signal }
        if case .failed = model.connectionState { return CueTheme.red }
        return CueTheme.secondaryInk
    }
}
