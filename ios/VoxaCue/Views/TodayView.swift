import SwiftUI
import VoxaCore

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.demoMode {
                    StatusPill(label: "Labeled demo scenario", symbol: "testtube.2", color: CueTheme.amber)
                }
                hero
                if let latest = model.sessions.first {
                    latestSession(latest)
                } else {
                    emptyHistory
                }
                privacyCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
        .background {
            ZStack(alignment: .topTrailing) {
                CueTheme.canvas
                Circle()
                    .fill(CueTheme.periwinkle.opacity(0.15))
                    .frame(width: 310, height: 310)
                    .blur(radius: 50)
                    .offset(x: 130, y: -160)
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .opacity(hasAppeared ? 1 : (reduceMotion ? 1 : 0))
        .offset(y: hasAppeared || reduceMotion ? 0 : 8)
        .onAppear {
            withAnimation(CueMotion.settle(reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                CueWordmark(compact: false)
                Spacer(minLength: 8)
                connectionPill
            }
            VStack(alignment: .leading, spacing: 10) {
                CueWordmark(compact: false)
                connectionPill
            }
        }
    }

    private var connectionPill: some View {
        StatusPill(
            label: model.connectionState.label,
            symbol: connectionSymbol,
            color: connectionColor
        )
    }

    private var hero: some View {
        PremiumCard(padding: dynamicTypeSize.isAccessibilitySize ? 20 : 24) {
            VStack(alignment: .leading, spacing: 22) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        heroCopy
                        Spacer(minLength: 10)
                        CuePulseGlyph(symbol: "waveform", size: 88, animated: true)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        CuePulseGlyph(symbol: "waveform", size: 78, animated: true)
                        heroCopy
                    }
                }

                Text("Set a target, place your phone nearby, and present naturally. Pace, filler words, and timing stay on-device during the session.")
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        readinessItem(symbol: "mic.fill", title: "Phone mic", detail: "On-device")
                        readinessItem(symbol: bandReadinessSymbol, title: "Cue Band", detail: bandReadinessDetail)
                    }
                    VStack(spacing: 10) {
                        readinessItem(symbol: "mic.fill", title: "Phone mic", detail: "On-device")
                        readinessItem(symbol: bandReadinessSymbol, title: "Cue Band", detail: bandReadinessDetail)
                    }
                }

                VoxaButton(
                    title: "Start a session",
                    symbol: "arrow.up.right",
                    style: .primary,
                    disabled: false,
                    action: { model.setupPresented = true }
                )
            }
        }
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            CueSectionLabel(text: "Ready when you are", color: CueTheme.green)
            Text("Speak with rhythm.\nStay in the room.")
                .font(.cueTitle)
                .foregroundStyle(CueTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readinessItem(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CueTheme.violet)
                .frame(width: 32, height: 32)
                .background(CueTheme.violetSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(CueTheme.ink)
                Text(detail)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(CueTheme.secondaryInk)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(CueTheme.canvas.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.small, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func latestSession(_ session: SessionSummary) -> some View {
        Button {
            model.selectedSummary = session
        } label: {
            PremiumCard(padding: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            CueSectionLabel(text: "Latest session", color: CueTheme.violet)
                            Text(session.name)
                                .font(.cueSection)
                                .foregroundStyle(CueTheme.ink)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CueTheme.violet)
                            .frame(width: 38, height: 38)
                            .background(CueTheme.violetSoft)
                            .clipShape(Circle())
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            compactMetric(value: "\(Int(session.averageWPM))", label: "WPM")
                            compactMetric(value: "\(session.fillerCount)", label: "Fillers")
                            compactMetric(value: session.durationSeconds.clockString, label: "Time")
                        }
                        VStack(spacing: 10) {
                            compactMetric(value: "\(Int(session.averageWPM))", label: "WPM")
                            compactMetric(value: "\(session.fillerCount)", label: "Fillers")
                            compactMetric(value: session.durationSeconds.clockString, label: "Time")
                        }
                    }
                }
            }
        }
        .buttonStyle(SpringPressStyle())
        .accessibilityHint("Opens the latest session summary")
    }

    private func compactMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .light).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
            CueSectionLabel(text: label, color: CueTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var emptyHistory: some View {
        PremiumCard(padding: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(CueTheme.signalGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Build your speaking baseline")
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                    Text("Complete one session to unlock real trends and evidence-based coaching.")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(CueTheme.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Raw audio is never saved")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CueTheme.ink)
                Text("History stores your transcript, metrics, cue outcomes, checkpoints, and any coaching you request—never the recording.")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }

    private var bandReadinessSymbol: String {
        if case .ready = model.connectionState { return "checkmark" }
        return "wave.3.right"
    }

    private var bandReadinessDetail: String {
        if case .ready = model.connectionState { return "Connected" }
        return "Optional"
    }

    private var connectionColor: Color {
        if case .ready = model.connectionState { return CueTheme.green }
        if case .reconnecting = model.connectionState { return CueTheme.amber }
        if case .failed = model.connectionState { return CueTheme.red }
        return CueTheme.secondaryInk
    }

    private var connectionSymbol: String {
        if case .ready = model.connectionState { return "checkmark.circle.fill" }
        if case .reconnecting = model.connectionState { return "arrow.triangle.2.circlepath" }
        if case .failed = model.connectionState { return "exclamationmark.triangle.fill" }
        return "applewatch.slash"
    }
}

extension TimeInterval {
    var clockString: String {
        let total = max(0, Int(self.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
