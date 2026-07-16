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
    @State private var deckPreparationID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(
                        eyebrow: "New session",
                        title: "Set your coaching target",
                        subtitle: "Cue uses these goals locally while you present. Every setting can be changed before the countdown."
                    )
                    basicsCard
                    paceCard
                    cueCard
                    preflightCard
                    VoxaButton(
                        title: "Begin presentation",
                        symbol: "arrow.up.right",
                        style: .primary,
                        disabled: startDisabled,
                        action: begin
                    )
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
                replanDeckForTargetDuration()
            }
        }
    }

    private var basicsCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Text("SESSION")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(CueTheme.violet)
                TextField("Session name", text: $name)
                    .font(.cueBody)
                    .padding(15)
                    .background(CueTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Picker("Mode", selection: $mode) {
                    ForEach(SessionMode.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target duration")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("Required for time cues")
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                    Spacer()
                    Stepper("\(Int(targetMinutes)) min", value: $targetMinutes, in: 1...30, step: 1)
                        .labelsHidden()
                    Text("\(Int(targetMinutes)) min")
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                }

                if mode == .powerPoint {
                    Divider().overlay(CueTheme.border)
                    Button {
                        showImporter = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: deckPlan == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(deckPlan == nil ? CueTheme.violet : CueTheme.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(deckTitle ?? "Upload PowerPoint")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(CueTheme.ink)
                                Text(deckPlan == nil ? "PPTX text and speaker notes become timed checkpoints" : "\(deckPlan?.checkpoints.count ?? 0) checkpoints ready")
                                    .font(.cueCaption)
                                    .foregroundStyle(CueTheme.secondaryInk)
                            }
                            Spacer()
                            if isPreparingDeck {
                                ProgressView().tint(CueTheme.violet)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(CueTheme.secondaryInk)
                            }
                        }
                    }
                    .buttonStyle(SpringPressStyle())
                    Text(
                        model.demoMode
                            ? "The PPTX binary and extracted text are not retained or sent in demo mode."
                            : "The PPTX binary is not retained. If the coaching API is configured, extracted text is sent only to prepare the checkpoint plan."
                    )
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                }
            }
        }
    }

    private var paceCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("PACE RANGE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(CueTheme.violet)
                    Spacer()
                    Text("\(Int(minimumWPM))–\(Int(maximumWPM)) WPM")
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                }
                VStack(spacing: 14) {
                    labeledSlider(label: "Minimum", value: $minimumWPM, range: 90...150)
                    labeledSlider(label: "Maximum", value: $maximumWPM, range: 140...210)
                }
                Text("A 20-second rolling window prevents one rushed sentence from causing a false cue.")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
            }
        }
    }

    private func labeledSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
                .frame(width: 58, alignment: .leading)
            Slider(value: value, in: range, step: 5)
                .tint(CueTheme.violet)
            Text("\(Int(value.wrappedValue))")
                .font(.cueCaption.monospacedDigit())
                .frame(width: 28, alignment: .trailing)
        }
    }

    private var cueCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("HAPTIC LANGUAGE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(CueTheme.violet)
                    Spacer()
                    Picker("Intensity", selection: $intensity) {
                        ForEach(CueIntensity.allCases, id: \.self) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .labelsHidden()
                }
                ForEach(CueKind.allCases, id: \.self) { cue in
                    Toggle(isOn: cueBinding(cue)) {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: cue))
                                .font(.system(size: 16, weight: .light))
                                .foregroundStyle(CueTheme.violet)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cue.label)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(CueTheme.ink)
                                Text(patternDescription(for: cue))
                                    .font(.cueCaption)
                                    .foregroundStyle(CueTheme.secondaryInk)
                            }
                        }
                    }
                    .tint(CueTheme.violet)
                }
            }
        }
    }

    private var preflightCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("PREFLIGHT")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(CueTheme.violet)
                preflightRow(
                    label: model.demoMode ? "Audio source" : "Phone microphone",
                    detail: model.demoMode ? "Deterministic simulation" : "Checked at countdown",
                    ready: true
                )
                preflightRow(
                    label: "Cue Band",
                    detail: model.connectionState.label,
                    ready: isCueReady
                )
                preflightRow(
                    label: "Presentation plan",
                    detail: mode == .freeSpeaking ? "Free speaking" : (deckPlan == nil ? "Upload required" : "Ready"),
                    ready: mode == .freeSpeaking || deckPlan != nil
                )
            }
        }
    }

    private func preflightRow(label: String, detail: String, ready: Bool) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ready ? CueTheme.green : CueTheme.amber)
            Text(label).font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            Text(detail).font(.cueCaption).foregroundStyle(CueTheme.secondaryInk)
        }
    }

    private var isCueReady: Bool {
        if case .ready = model.connectionState { return true }
        return false
    }

    private var startDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || minimumWPM >= maximumWPM
            || enabledCues.isEmpty
            || isPreparingDeck
            || (mode == .powerPoint && deckPlan == nil)
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
        case .tooFast: "Two short pulses"
        case .tooSlow: "One long pulse"
        case .fillerBurst: "Three short pulses"
        case .deckBehind: "Long, short, long"
        case .time75: "One pronounced pulse"
        case .time90: "Two pronounced pulses"
        case .time100: "Three pronounced pulses"
        }
    }

    private func handleImport(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            model.lastError = "The PowerPoint file could not be opened."
            return
        }
        let preparationID = UUID()
        deckPreparationID = preparationID
        isPreparingDeck = true
        deckTitle = url.deletingPathExtension().lastPathComponent
        deckSlides = []
        deckPlan = nil
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let slides = try await Task.detached {
                    try PowerPointParser().parse(url: url)
                }.value
                guard deckPreparationID == preparationID else { return }
                let title = deckTitle ?? "Presentation"
                deckSlides = slides
                let plan = await model.createDeckPlan(
                    title: title,
                    targetDurationSeconds: Int(targetMinutes * 60),
                    slides: slides
                )
                guard deckPreparationID == preparationID else { return }
                deckPlan = plan
            } catch {
                guard deckPreparationID == preparationID else { return }
                deckSlides = []
                deckPlan = nil
                model.lastError = "Cue could not extract slide text from this PowerPoint."
            }
            guard deckPreparationID == preparationID else { return }
            isPreparingDeck = false
        }
    }

    private func replanDeckForTargetDuration() {
        guard let title = deckTitle, !deckSlides.isEmpty else { return }
        let preparationID = UUID()
        let slides = deckSlides
        let targetDurationSeconds = Int(targetMinutes * 60)
        deckPreparationID = preparationID
        isPreparingDeck = true
        Task {
            let plan = await model.createDeckPlan(
                title: title,
                targetDurationSeconds: targetDurationSeconds,
                slides: slides
            )
            guard deckPreparationID == preparationID else { return }
            deckPlan = plan
            isPreparingDeck = false
        }
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
