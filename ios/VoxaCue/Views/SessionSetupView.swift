import SwiftUI
import UniformTypeIdentifiers
import VoxaCore
import VoxaRuntime

struct SessionSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Practice Session"
    @State private var mode = SessionMode.freeSpeaking
    @State private var targetMinutes = 5.0
    @State private var minimumWPM = 130.0
    @State private var maximumWPM = 160.0
    @State private var intensity = CueIntensity.medium
    @State private var enabledCues = Set(CueKind.allCases)
    @State private var showImporter = false
    @State private var isPreparingDeck = false
    @State private var deckTitle: String?
    @State private var deckSlides: [DeckSlide] = []
    @State private var deckPlan: DeckPlan?
    @State private var deckPlanSource: DeckPlanSource?
    @State private var deckTimingAdjustedLocally = false
    @State private var deckPreparationID: UUID?
    @State private var deckPreparationTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(
                        eyebrow: "New session",
                        title: "Set your coaching target",
                        subtitle: "Choose what Cue should watch. Your live coaching settings stay on this iPhone."
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
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "pptx") ?? .data],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
            .onChange(of: targetMinutes) { _, _ in
                retimePreparedDeck()
            }
            .onDisappear {
                deckPreparationTask?.cancel()
            }
        }
    }

    private var basicsCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                CueSectionLabel(text: "Session", color: CueTheme.violet)
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

                Picker("Session mode", selection: $mode) {
                    ForEach(SessionMode.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(value: $targetMinutes, in: 1...30, step: 1) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Target duration")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(CueTheme.ink)
                            Text("Drives time and deck-progress cues")
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Text("\(Int(targetMinutes)) min")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(CueTheme.violet)
                    }
                }

                if mode == .powerPoint {
                    Divider().overlay(CueTheme.border)
                    Button {
                        showImporter = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: deckPlan == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                                .font(.system(size: 21, weight: .medium))
                                .foregroundStyle(deckPlan == nil ? CueTheme.violet : CueTheme.green)
                                .frame(width: 40, height: 40)
                                .background((deckPlan == nil ? CueTheme.violetSoft : CueTheme.green.opacity(0.10)))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(deckTitle ?? "Choose a PowerPoint")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(CueTheme.ink)
                                    .lineLimit(2)
                                Text(deckStatusLabel)
                                    .font(.cueCaption)
                                    .foregroundStyle(CueTheme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if isPreparingDeck {
                                ProgressView().tint(CueTheme.violet)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CueTheme.secondaryInk)
                            }
                        }
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(SpringPressStyle())
                    Text(deckPrivacyCopy)
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var deckStatusLabel: String {
        guard let deckPlan else {
            return "PPTX text and notes become timed checkpoints"
        }
        let source = deckPlanSource?.label ?? "Prepared"
        let timing = deckTimingAdjustedLocally ? " · timing adjusted locally" : ""
        return "\(deckPlan.checkpoints.count) checkpoints · \(source)\(timing)"
    }

    private var deckPrivacyCopy: String {
        if model.demoMode {
            return "The file stays local and is not retained. Demo mode prepares checkpoints on-device."
        }
        return "The file is never retained. Extracted text is sent only if the coaching API is configured; local planning remains available."
    }

    private var paceCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    CueSectionLabel(text: "Pace range", color: CueTheme.violet)
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
                        ? "Cue evaluates a rolling window so one rushed sentence does not trigger a false alert."
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
                .tint(CueTheme.violet)
                .accessibilityLabel("\(label) speaking pace")
                .accessibilityValue("\(Int(value.wrappedValue)) words per minute")
        }
    }

    private var cueCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        CueSectionLabel(text: "Haptic language", color: CueTheme.violet)
                        Spacer(minLength: 8)
                        intensityPicker
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        CueSectionLabel(text: "Haptic language", color: CueTheme.violet)
                        intensityPicker
                    }
                }
                ForEach(CueKind.allCases, id: \.self) { cue in
                    Toggle(isOn: cueBinding(cue)) {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: cue))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(CueTheme.violet)
                                .frame(width: 32, height: 32)
                                .background(CueTheme.violetSoft)
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
                    .tint(CueTheme.violet)
                }
                if enabledCues.isEmpty {
                    Label("No wrist cues selected. The session will still record analytics.", systemImage: "chart.xyaxis.line")
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
                CueSectionLabel(text: "Preflight", color: CueTheme.violet)
                preflightRow(
                    label: model.demoMode ? "Audio source" : "Phone microphone",
                    detail: model.demoMode ? "Deterministic simulation" : "Permission checked when you begin",
                    state: model.demoMode ? .ready : .pending
                )
                preflightRow(
                    label: "Cue Band",
                    detail: bandPreflightDetail,
                    state: bandPreflightState
                )
                if !isCueReady {
                    Button {
                        model.connectCueBand()
                    } label: {
                        Label("Connect Cue Band", systemImage: "wave.3.right")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(CueTheme.violet)
                    .disabled(bandConnectionIsBusy)
                }
                preflightRow(
                    label: "Presentation plan",
                    detail: mode == .freeSpeaking ? "Free speaking" : (deckPlan == nil ? "PowerPoint required" : "Ready"),
                    state: mode == .freeSpeaking || deckPlan != nil ? .ready : .blocked
                )
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
        if isPreparingDeck {
            return "Your presentation plan is still being prepared."
        }
        if mode == .powerPoint && deckPlan == nil {
            return "Choose a PowerPoint to use presentation-progress cues."
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
        case .deckBehind: "Long, short, long · move forward"
        case .time75: "One pronounced pulse · 75% elapsed"
        case .time90: "Two pronounced pulses · 90% elapsed"
        case .time100: "Three pronounced pulses · target reached"
        }
    }

    private func handleImport(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            model.lastError = "The PowerPoint file could not be opened. Choose a .pptx file and try again."
            return
        }
        deckPreparationTask?.cancel()
        let preparationID = UUID()
        deckPreparationID = preparationID
        isPreparingDeck = true
        deckTitle = url.deletingPathExtension().lastPathComponent
        deckSlides = []
        deckPlan = nil
        deckPlanSource = nil
        deckTimingAdjustedLocally = false
        deckPreparationTask = Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let slides = try await Task.detached {
                    try PowerPointParser().parse(url: url)
                }.value
                try Task.checkCancellation()
                guard deckPreparationID == preparationID else { return }
                let title = deckTitle ?? "Presentation"
                deckSlides = slides
                let requestedTargetDurationSeconds = Int(targetMinutes * 60)
                let prepared = await model.createDeckPlan(
                    title: title,
                    targetDurationSeconds: requestedTargetDurationSeconds,
                    slides: slides
                )
                try Task.checkCancellation()
                guard deckPreparationID == preparationID else { return }
                let latestTargetDurationSeconds = Int(targetMinutes * 60)
                let reconciled = reconciledPreparedDeck(
                    prepared,
                    requestedTargetDurationSeconds: requestedTargetDurationSeconds,
                    latestTargetDurationSeconds: latestTargetDurationSeconds
                )
                deckPlan = reconciled.plan
                deckPlanSource = reconciled.source
                deckTimingAdjustedLocally = requestedTargetDurationSeconds != latestTargetDurationSeconds
            } catch is CancellationError {
                return
            } catch {
                guard deckPreparationID == preparationID else { return }
                deckSlides = []
                deckPlan = nil
                deckPlanSource = nil
                model.lastError = "Cue could not extract slide text from that file. Confirm it is a valid .pptx and try again."
            }
            guard deckPreparationID == preparationID else { return }
            isPreparingDeck = false
        }
    }

    private func retimePreparedDeck() {
        guard let deckPlan else { return }
        self.deckPlan = LocalDeckPlanner.retime(
            plan: deckPlan,
            targetDurationSeconds: Int(targetMinutes * 60)
        )
        deckTimingAdjustedLocally = true
    }

    private func begin() {
        let intensityMap = Dictionary(uniqueKeysWithValues: CueKind.allCases.map { ($0, intensity) })
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
            mode: mode,
            targetDurationSeconds: targetMinutes * 60,
            profile: profile,
            deckPlan: mode == .powerPoint ? deckPlan : nil
        )
        model.beginSession(configuration: configuration)
    }
}

func reconciledPreparedDeck(
    _ prepared: PreparedDeckPlan,
    requestedTargetDurationSeconds: Int,
    latestTargetDurationSeconds: Int
) -> PreparedDeckPlan {
    guard requestedTargetDurationSeconds != latestTargetDurationSeconds else { return prepared }
    return PreparedDeckPlan(
        plan: LocalDeckPlanner.retime(
            plan: prepared.plan,
            targetDurationSeconds: latestTargetDurationSeconds
        ),
        source: prepared.source
    )
}

private enum PreflightState {
    case ready
    case pending
    case optional
    case blocked

    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .optional: "minus.circle.fill"
        case .blocked: "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: CueTheme.green
        case .pending: CueTheme.violet
        case .optional: CueTheme.secondaryInk
        case .blocked: CueTheme.red
        }
    }
}
