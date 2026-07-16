import SwiftUI
import VoxaCore

struct LiveSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: LiveSessionController
    @State private var confirmEnd = false
    @State private var confirmDiscard = false
    @State private var showDetails = false

    var body: some View {
        ZStack {
            background
            switch session.phase {
            case .preparing:
                preparationView
            case let .countdown(count):
                countdownView(count)
            case .recording, .paused:
                liveView
            case .finalizing:
                finalizingView
            case let .failed(message):
                failureView(message)
            }
        }
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and save", role: .destructive) {
                Task { await session.finish() }
            }
            Button("Keep presenting", role: .cancel) {}
        } message: {
            Text("Cue will finalize the transcript and save your local analytics. Raw audio is never saved.")
        }
        .confirmationDialog("Discard this partial session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard session", role: .destructive) {
                model.activeSession = nil
            }
            Button("Keep partial session", role: .cancel) {}
        } message: {
            Text("The current transcript and metrics will be permanently discarded.")
        }
    }

    private var background: some View {
        ZStack(alignment: .topTrailing) {
            CueTheme.canvas
            Circle()
                .fill(CueTheme.periwinkle.opacity(0.13))
                .frame(width: 320, height: 320)
                .blur(radius: 55)
                .offset(x: 140, y: -160)
        }
        .ignoresSafeArea()
    }

    private var preparationView: some View {
        VStack(spacing: 24) {
            CueWordmark(compact: false)
            CuePulseGlyph(symbol: model.demoMode ? "testtube.2" : "waveform", size: 132, animated: true)
            Text(model.demoMode ? "Preparing the demo scenario" : "Preparing on-device speech")
                .font(.cueSection)
                .foregroundStyle(CueTheme.ink)
                .multilineTextAlignment(.center)
            Text(
                model.demoMode
                    ? "No microphone audio is captured in this labeled simulation."
                    : "Speech assets and microphone access are checked before the countdown begins."
            )
            .font(.cueBody)
            .foregroundStyle(CueTheme.secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
    }

    private func countdownView(_ count: Int) -> some View {
        VStack(spacing: 18) {
            CueSectionLabel(text: "Ready", color: CueTheme.violet)
            Text("\(count)")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 90 : 120, weight: .ultraLight, design: .rounded).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text("Place your phone nearby with the microphone clear")
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.72), trigger: count)
    }

    private var liveView: some View {
        VStack(spacing: 0) {
            liveHeader
            ScrollView {
                VStack(spacing: 18) {
                    if session.isPaused { pauseBanner }
                    timeRing
                    paceStatus
                    if let latestCue = session.cueLogs.last { lastCueCard(latestCue) }
                    if session.configuration.deckPlan != nil { checkpointCard }
                    detailsControl
                    if showDetails {
                        metricGrid
                        transcriptCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .animation(CueMotion.settle(reduceMotion: reduceMotion), value: showDetails)
                .animation(CueMotion.quick(reduceMotion: reduceMotion), value: session.cueLogs.last)
            }
            controls
        }
    }

    private var liveHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                StatusPill(label: liveSourceLabel, symbol: liveSourceSymbol, color: liveSourceColor)
                Spacer(minLength: 4)
                StatusPill(label: bandStatusLabel, symbol: bandStatusSymbol, color: bandStatusColor)
            }
            VStack(alignment: .leading, spacing: 8) {
                StatusPill(label: liveSourceLabel, symbol: liveSourceSymbol, color: liveSourceColor)
                StatusPill(label: bandStatusLabel, symbol: bandStatusSymbol, color: bandStatusColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var pauseBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pause.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CueTheme.amber)
                .frame(width: 36, height: 36)
                .background(CueTheme.amber.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(pauseHeadline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CueTheme.ink)
                Text(pauseMessage)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(16)
        .background(CueTheme.amber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous)
                .stroke(CueTheme.amber.opacity(0.24), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private var timeRing: some View {
        ZStack {
            Circle()
                .stroke(CueTheme.border.opacity(0.78), lineWidth: 12)
            Circle()
                .trim(from: 0, to: presentationProgress)
                .stroke(
                    CueTheme.signalGradient,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.45), value: presentationProgress)
            VStack(spacing: 5) {
                Text(session.metrics.elapsedSeconds.clockString)
                    .font(.system(.largeTitle, design: .rounded, weight: .light).monospacedDigit())
                    .foregroundStyle(CueTheme.ink)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                Text("of \(session.configuration.targetDurationSeconds.clockString)")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
            }
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 198 : 218, height: dynamicTypeSize.isAccessibilitySize ? 198 : 218)
        .padding(.top, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Presentation time")
        .accessibilityValue("\(session.metrics.elapsedSeconds.clockString) of \(session.configuration.targetDurationSeconds.clockString)")
    }

    private var presentationProgress: Double {
        guard session.configuration.targetDurationSeconds > 0 else { return 0 }
        return min(1, session.metrics.elapsedSeconds / session.configuration.targetDurationSeconds)
    }

    private var paceStatus: some View {
        VStack(spacing: 6) {
            Text("\(Int(session.metrics.rollingWPM.rounded()))")
                .font(.system(.largeTitle, design: .rounded, weight: .light).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
                .contentTransition(reduceMotion ? .identity : .numericText())
            CueSectionLabel(text: "Words per minute", color: CueTheme.secondaryInk)
            StatusPill(label: paceLabel, symbol: paceSymbol, color: paceColor)
                .padding(.top, 3)
        }
        .accessibilityElement(children: .combine)
    }

    private var metricGrid: some View {
        CueMetricGrid(spacing: 12) {
            MetricTile(
                label: "Fillers",
                value: "\(session.metrics.fillerCount)",
                detail: session.metrics.fillerCount < 2 ? "Clean delivery" : "Pause and reset",
                tint: session.metrics.fillerCount < 2 ? CueTheme.green : CueTheme.amber
            )
            MetricTile(
                label: "Talk ratio",
                value: "\(Int(session.metrics.talkRatio * 100))%",
                detail: "Active speaking",
                tint: CueTheme.violet
            )
            MetricTile(
                label: "Cues completed",
                value: "\(session.cueLogs.filter { $0.deliveryStatus == .completed }.count)",
                detail: model.demoMode ? "Simulated" : (isCueReady ? "Confirmed by band" : "Analytics only"),
                tint: model.demoMode ? CueTheme.violet : (isCueReady ? CueTheme.green : CueTheme.secondaryInk)
            )
            MetricTile(
                label: model.demoMode ? "Simulated level" : "Mic level",
                value: "\(Int(session.microphoneLevel * 100))",
                detail: model.demoMode
                    ? "Demo fixture"
                    : (session.microphoneLevel > 0.18 ? "Signal healthy" : "Move phone closer"),
                tint: model.demoMode || session.microphoneLevel > 0.18 ? CueTheme.green : CueTheme.amber
            )
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    private var checkpointCard: some View {
        PremiumCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CueSectionLabel(text: "Content progress", color: CueTheme.violet)
                    Spacer()
                    Text("\(Int(session.checkpointProgress * 100))%")
                        .font(.cueCaption.monospacedDigit())
                        .foregroundStyle(CueTheme.secondaryInk)
                }
                Text(session.currentCheckpointLabel ?? "Listening for your first checkpoint")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CueTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { geometry in
                    Capsule()
                        .fill(CueTheme.border)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(CueTheme.signalGradient)
                                .frame(width: geometry.size.width * session.checkpointProgress)
                        }
                }
                .frame(height: 7)
            }
        }
    }

    private var detailsControl: some View {
        Button {
            showDetails.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: showDetails ? "eye.slash" : "chart.xyaxis.line")
                Text(showDetails ? "Hide live details" : "Show live details")
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(showDetails ? 180 : 0))
                    .animation(CueMotion.quick(reduceMotion: reduceMotion), value: showDetails)
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(CueTheme.violet)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(CueTheme.violetSoft.opacity(0.72))
            .clipShape(Capsule())
        }
        .buttonStyle(SpringPressStyle())
        .accessibilityHint("Live details are optional while presenting")
    }

    private var transcriptCard: some View {
        PremiumCard(padding: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    CueSectionLabel(text: "Live transcript", color: CueTheme.violet)
                    Spacer()
                    Label("Not audio", systemImage: "lock.fill")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(CueTheme.green)
                }
                Text(transcriptText)
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    private func lastCueCard(_ cue: LiveSessionController.CueLog) -> some View {
        let presentation = cueDeliveryPresentation(status: cue.deliveryStatus, demoMode: model.demoMode)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(presentation.color)
                .frame(width: 38, height: 38)
                .background(presentation.color.opacity(0.11))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("\(presentation.label) · \(cue.decision.kind.label)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CueTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(cue.decision.reason)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(16)
        .background(presentation.color.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous)
                .stroke(presentation.color.opacity(0.20), lineWidth: 0.75)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                pauseButton
                endButton
            }
            VStack(spacing: 10) {
                pauseButton
                endButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var pauseButton: some View {
        Button {
            session.togglePause()
        } label: {
            Label(
                session.isPaused ? "Resume presentation" : "Pause for Q&A",
                systemImage: session.isPaused ? "play.fill" : "pause.fill"
            )
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(CueTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(CueTheme.surface)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(CueTheme.border, lineWidth: 0.75) }
        }
        .buttonStyle(SpringPressStyle())
    }

    private var endButton: some View {
        Button {
            confirmEnd = true
        } label: {
            Label("End session", systemImage: "stop.fill")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(CueTheme.signalGradient)
                .clipShape(Capsule())
        }
        .buttonStyle(SpringPressStyle())
    }

    private var finalizingView: some View {
        VStack(spacing: 22) {
            CuePulseGlyph(symbol: "checkmark", size: 124, animated: true)
            Text("Finalizing your session")
                .font(.cueSection)
                .foregroundStyle(CueTheme.ink)
            Text("Saving the final transcript and local metrics. Raw audio is never stored.")
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(CueTheme.red)
                .frame(width: 82, height: 82)
                .background(CueTheme.red.opacity(0.10))
                .clipShape(Circle())
            Text(session.hasStarted ? "Session stopped" : "Session could not start")
                .font(.cueTitle)
                .foregroundStyle(CueTheme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if session.hasStarted {
                VoxaButton(
                    title: "Save partial session",
                    symbol: "square.and.arrow.down",
                    style: .primary,
                    disabled: false,
                    action: { Task { await session.finish() } }
                )
                Button("Discard partial session", role: .destructive) {
                    confirmDiscard = true
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .frame(minHeight: 44)
                .buttonStyle(SpringPressStyle())
            } else {
                VoxaButton(
                    title: "Return to Today",
                    symbol: "arrow.left",
                    style: .primary,
                    disabled: false,
                    action: { model.activeSession = nil }
                )
            }
        }
        .padding(28)
    }

    private var transcriptText: String {
        let combined = [session.liveTranscript, session.volatileTranscript].filter { !$0.isEmpty }.joined(separator: " ")
        return combined.isEmpty ? "Listening for your first words…" : combined
    }

    private var isCueReady: Bool {
        guard session.latestBandFailure == nil else { return false }
        if case .ready = model.connectionState { return true }
        return false
    }

    private var bandStatusLabel: String {
        if let failure = session.latestBandFailure { return failure }
        if isCueReady { return "Cue Band connected" }
        return "Analytics only"
    }

    private var bandStatusSymbol: String {
        if session.latestBandFailure != nil { return "exclamationmark.triangle.fill" }
        return isCueReady ? "checkmark.circle.fill" : "chart.xyaxis.line"
    }

    private var bandStatusColor: Color {
        if session.latestBandFailure != nil { return CueTheme.red }
        return isCueReady ? CueTheme.green : CueTheme.secondaryInk
    }

    private var liveSourceLabel: String {
        if session.isPaused { return "Analysis paused" }
        return model.demoMode ? "Labeled simulation" : "Phone microphone active"
    }

    private var liveSourceSymbol: String {
        if session.isPaused { return "pause.circle.fill" }
        return model.demoMode ? "testtube.2" : "mic.fill"
    }

    private var liveSourceColor: Color {
        if session.isPaused { return CueTheme.amber }
        return model.demoMode ? CueTheme.violet : CueTheme.green
    }

    private var pauseHeadline: String {
        switch session.pauseReason {
        case .appInactive: "Paused when Voxa Cue left the foreground"
        case .user, .none: "Paused for Q&A"
        }
    }

    private var pauseMessage: String {
        switch session.pauseReason {
        case .appInactive:
            "Microphone analysis and presentation timing stopped automatically. Tap Resume presentation when you are ready."
        case .user, .none:
            "The presentation clock, microphone analysis, and live cues are paused."
        }
    }

    private var paceLabel: String {
        let wpm = session.metrics.rollingWPM
        if wpm == 0 { return "Finding your rhythm" }
        if wpm > session.configuration.profile.maximumWPM { return "Above target" }
        if wpm < session.configuration.profile.minimumWPM { return "Below target" }
        return "On target"
    }

    private var paceSymbol: String {
        switch paceLabel {
        case "On target": "checkmark"
        case "Finding your rhythm": "waveform"
        default: "waveform.path.ecg"
        }
    }

    private var paceColor: Color {
        switch paceLabel {
        case "On target": CueTheme.green
        case "Finding your rhythm": CueTheme.violet
        default: CueTheme.amber
        }
    }
}

enum CueDeliveryPresentation: Equatable {
    case simulated
    case sending
    case accepted
    case completed
    case failed
    case analyticsOnly

    var label: String {
        switch self {
        case .simulated: "Simulated cue"
        case .sending: "Sending to band"
        case .accepted: "Accepted by band"
        case .completed: "Completed on band"
        case .failed: "Band delivery failed"
        case .analyticsOnly: "Analytics-only cue"
        }
    }

    var symbol: String {
        switch self {
        case .simulated: "testtube.2"
        case .sending: "arrow.up.circle.fill"
        case .accepted: "clock.badge.checkmark.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .analyticsOnly: "chart.xyaxis.line"
        }
    }

    var color: Color {
        switch self {
        case .simulated, .sending: CueTheme.violet
        case .accepted: CueTheme.amber
        case .completed: CueTheme.green
        case .failed: CueTheme.red
        case .analyticsOnly: CueTheme.secondaryInk
        }
    }
}

func cueDeliveryPresentation(status: CueDeliveryStatus, demoMode: Bool) -> CueDeliveryPresentation {
    if demoMode { return .simulated }
    return switch status {
    case .pending: .sending
    case .accepted: .accepted
    case .completed: .completed
    case .failed: .failed
    case .notConnected, .suppressed: .analyticsOnly
    }
}
