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
        .background(CueTheme.canvas.ignoresSafeArea())
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
        HeroCard(padding: dynamicTypeSize.isAccessibilitySize ? 20 : 24) {
            VStack(alignment: .leading, spacing: 22) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        heroCopy
                        Spacer(minLength: 10)
                        SectionMark(assetName: "VoiceSignal", size: 88)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        SectionMark(assetName: "VoiceSignal", size: 78)
                        heroCopy
                    }
                }

                Text("Set your target, place your phone nearby, and speak.")
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
                    title: primaryActionTitle,
                    symbol: model.cueBandIsReady ? "arrow.up.right" : "wave.3.right",
                    style: .primary,
                    disabled: bandConnectionIsBusy,
                    action: primaryAction
                )
                if model.cueBandIsReady {
                    Button {
                        model.presentSessionSetup(intent: .presentation)
                    } label: {
                        Label("Use a presentation", systemImage: "rectangle.stack")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(CueTheme.signal)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var primaryActionTitle: String {
        if model.cueBandIsReady { return "Start a session" }
        if bandConnectionIsBusy { return model.connectionState.label }
        return "Connect Cue Band"
    }

    private func primaryAction() {
        if model.cueBandIsReady {
            model.presentSessionSetup(intent: .freeSpeaking)
        } else {
            model.connectCueBand()
        }
    }

    private var bandConnectionIsBusy: Bool {
        switch model.connectionState {
        case .searching, .connecting, .discovering, .reconnecting: true
        case .idle, .bluetoothUnavailable, .ready, .failed: false
        }
    }

    private var heroCopy: some View {
        Text("Ready to rehearse?")
            .font(.cueTitle)
            .foregroundStyle(CueTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func readinessItem(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CueTheme.signal)
                .frame(width: 32, height: 32)
                .background(CueTheme.signalSoft)
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
                            CueSectionLabel(text: "Latest session", color: CueTheme.signal)
                            Text(session.name)
                                .font(.cueSection)
                                .foregroundStyle(CueTheme.ink)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CueTheme.signal)
                            .frame(width: 38, height: 38)
                            .background(CueTheme.signalSoft)
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
                SectionMark(assetName: "DeliveryAnalytics", size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Build your speaking baseline")
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                    Text("Complete one session to unlock trends and coaching.")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var privacyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(CueTheme.green)
            Text("Raw audio is never saved")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(CueTheme.ink)
        }
        .padding(.horizontal, 4)
    }

    private var bandReadinessSymbol: String {
        if case .ready = model.connectionState { return "checkmark" }
        return "wave.3.right"
    }

    private var bandReadinessDetail: String {
        if model.cueBandIsReady { return "Connected" }
        return "Required"
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
