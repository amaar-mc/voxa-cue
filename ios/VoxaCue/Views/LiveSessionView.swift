import SwiftUI
import VoxaCore

struct LiveSessionView: View {
    @Environment(AppModel.self) private var model
    let session: LiveSessionController
    @State private var confirmEnd = false

    var body: some View {
        ZStack {
            CueTheme.canvas.ignoresSafeArea()
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
            Text("Cue will finalize the transcript and save your local analytics.")
        }
    }

    private var preparationView: some View {
        VStack(spacing: 24) {
            CueWordmark(compact: false)
            ProgressView()
                .controlSize(.large)
                .tint(CueTheme.violet)
            Text(model.demoMode ? "Preparing deterministic demo" : "Preparing on-device speech")
                .font(.cueSection)
                .foregroundStyle(CueTheme.ink)
            Text(
                model.demoMode
                    ? "No microphone audio is captured in this labeled simulation."
                    : "Keep the phone nearby with its microphone unobstructed."
            )
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private func countdownView(_ count: Int) -> some View {
        VStack(spacing: 18) {
            Text("READY")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(CueTheme.violet)
            Text("\(count)")
                .font(.system(size: 120, weight: .ultraLight, design: .rounded).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
                .contentTransition(.numericText())
            Text("Your live screen will remain awake")
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var liveView: some View {
        VStack(spacing: 0) {
            liveHeader
            ScrollView {
                VStack(spacing: 20) {
                    timeRing
                    paceStatus
                    metricGrid
                    if session.configuration.deckPlan != nil { checkpointCard }
                    transcriptCard
                    if let cue = session.lastCue { lastCueCard(cue) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            controls
        }
    }

    private var liveHeader: some View {
        HStack {
            StatusPill(
                label: liveSourceLabel,
                symbol: liveSourceSymbol,
                color: liveSourceColor
            )
            Spacer()
            StatusPill(
                label: bandStatusLabel,
                symbol: bandStatusSymbol,
                color: bandStatusColor
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var timeRing: some View {
        ZStack {
            Circle()
                .stroke(CueTheme.border.opacity(0.75), lineWidth: 13)
            Circle()
                .trim(from: 0, to: min(1, session.metrics.elapsedSeconds / session.configuration.targetDurationSeconds))
                .stroke(
                    AngularGradient(colors: [CueTheme.violet, CueTheme.greenBright], center: .center),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.88), value: session.metrics.elapsedSeconds)
            VStack(spacing: 5) {
                Text(session.metrics.elapsedSeconds.clockString)
                    .font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(CueTheme.ink)
                Text("of \(session.configuration.targetDurationSeconds.clockString)")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
            }
        }
        .frame(width: 218, height: 218)
        .padding(.top, 8)
    }

    private var paceStatus: some View {
        VStack(spacing: 5) {
            Text("\(Int(session.metrics.rollingWPM.rounded()))")
                .font(.system(size: 58, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
                .contentTransition(.numericText())
            Text("WORDS PER MINUTE")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(CueTheme.secondaryInk)
            StatusPill(label: paceLabel, symbol: paceSymbol, color: paceColor)
                .padding(.top, 4)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(
                label: "Fillers",
                value: "\(session.metrics.fillerCount)",
                detail: session.metrics.fillerCount < 2 ? "Clean delivery" : "Reset available",
                tint: session.metrics.fillerCount < 2 ? CueTheme.green : CueTheme.amber
            )
            MetricTile(
                label: "Talk ratio",
                value: "\(Int(session.metrics.talkRatio * 100))%",
                detail: "Active speaking",
                tint: CueTheme.violet
            )
            MetricTile(
                label: "Cues acknowledged",
                value: "\(session.cueLogs.filter { $0.deliveryStatus == .accepted || $0.deliveryStatus == .completed }.count)",
                detail: session.latestBandFailure == nil
                    ? (isCueReady ? "Confirmed by band" : "Analytics only")
                    : "Last cue failed",
                tint: isCueReady ? CueTheme.green : CueTheme.secondaryInk
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
    }

    private var checkpointCard: some View {
        PremiumCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("CONTENT PROGRESS", systemImage: "rectangle.stack")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(CueTheme.violet)
                    Spacer()
                    Text("\(Int(session.checkpointProgress * 100))%")
                        .font(.cueCaption.monospacedDigit())
                        .foregroundStyle(CueTheme.secondaryInk)
                }
                Text(session.currentCheckpointLabel ?? "Listening for your first checkpoint")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(CueTheme.ink)
                GeometryReader { geometry in
                    Capsule()
                        .fill(CueTheme.border)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(CueTheme.violet)
                                .frame(width: geometry.size.width * session.checkpointProgress)
                        }
                }
                .frame(height: 7)
            }
        }
    }

    private var transcriptCard: some View {
        PremiumCard(padding: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text("LIVE TRANSCRIPT")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(CueTheme.violet)
                Text(transcriptText)
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func lastCueCard(_ cue: CueDecision) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(CueTheme.violet)
            VStack(alignment: .leading, spacing: 3) {
                Text("Latest cue · \(cue.kind.label)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CueTheme.ink)
                Text(cue.reason)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
            }
            Spacer()
        }
        .padding(16)
        .background(CueTheme.violetSoft.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                session.togglePause()
            } label: {
                Label(session.phase == .paused ? "Resume" : "Q&A / Pause", systemImage: session.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CueTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(CueTheme.surface)
                    .clipShape(Capsule())
            }
            .buttonStyle(SpringPressStyle())
            Button {
                confirmEnd = true
            } label: {
                Label("End", systemImage: "stop.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 112, height: 54)
                    .background(CueTheme.navy)
                    .clipShape(Capsule())
            }
            .buttonStyle(SpringPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(CueTheme.canvas.opacity(0.96))
    }

    private var finalizingView: some View {
        VStack(spacing: 22) {
            ProgressView().controlSize(.large).tint(CueTheme.violet)
            Text("Finalizing your session")
                .font(.cueSection)
                .foregroundStyle(CueTheme.ink)
            Text("Committing the final transcript and local metrics. No audio is being saved.")
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(CueTheme.amber)
            Text(session.hasStarted ? "Session stopped" : "Session could not start")
                .font(.cueTitle)
                .foregroundStyle(CueTheme.ink)
            Text(message)
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .multilineTextAlignment(.center)
            if session.hasStarted {
                VoxaButton(
                    title: "Save partial session",
                    symbol: "square.and.arrow.down",
                    style: .primary,
                    disabled: false,
                    action: { Task { await session.finish() } }
                )
                Button("Discard and return", role: .destructive) {
                    model.activeSession = nil
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
        session.latestBandFailure ?? model.connectionState.label
    }

    private var bandStatusSymbol: String {
        if session.latestBandFailure != nil { return "exclamationmark.triangle.fill" }
        return isCueReady ? "checkmark.circle.fill" : "applewatch.slash"
    }

    private var bandStatusColor: Color {
        if session.latestBandFailure != nil { return CueTheme.red }
        return isCueReady ? CueTheme.green : CueTheme.secondaryInk
    }

    private var liveSourceLabel: String {
        if session.phase == .paused { return "Analysis paused" }
        return model.demoMode ? "Demo audio simulation" : "Phone microphone active"
    }

    private var liveSourceSymbol: String {
        if session.phase == .paused { return "pause.circle.fill" }
        return model.demoMode ? "testtube.2" : "mic.fill"
    }

    private var liveSourceColor: Color {
        if session.phase == .paused || model.demoMode { return CueTheme.amber }
        return CueTheme.green
    }

    private var paceLabel: String {
        let wpm = session.metrics.rollingWPM
        if wpm == 0 { return "Finding your rhythm" }
        if wpm > session.configuration.profile.maximumWPM { return "Above target" }
        if wpm < session.configuration.profile.minimumWPM { return "Below target" }
        return "On target"
    }

    private var paceSymbol: String {
        paceLabel == "On target" ? "checkmark" : "waveform.path.ecg"
    }

    private var paceColor: Color {
        paceLabel == "On target" ? CueTheme.green : CueTheme.amber
    }
}
