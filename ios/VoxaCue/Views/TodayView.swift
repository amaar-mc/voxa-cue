import SwiftUI
import VoxaCore

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.demoMode {
                    StatusPill(label: "Deterministic demo data", symbol: "testtube.2", color: CueTheme.amber)
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
            .padding(.bottom, 32)
        }
        .background(CueTheme.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .center) {
            CueWordmark(compact: false)
            Spacer()
            StatusPill(
                label: model.connectionState.label,
                symbol: connectionSymbol,
                color: connectionColor
            )
        }
    }

    private var hero: some View {
        PremiumCard(padding: 24) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("READY WHEN YOU ARE")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(CueTheme.green)
                        Text("Stay present.\nCue handles the rest.")
                            .font(.system(size: 30, weight: .light, design: .rounded))
                            .foregroundStyle(CueTheme.ink)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(CueTheme.border, lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: 0.72)
                            .stroke(CueTheme.greenBright, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "waveform")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(CueTheme.violet)
                    }
                    .frame(width: 78, height: 78)
                }
                Text("Set your target, place the phone nearby, and start presenting. Live coaching stays local and private.")
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(3)
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

    private func latestSession(_ session: SessionSummary) -> some View {
        Button {
            model.selectedSummary = session
        } label: {
            PremiumCard(padding: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("LATEST SESSION")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .tracking(1.3)
                                .foregroundStyle(CueTheme.violet)
                            Text(session.name)
                                .font(.cueSection)
                                .foregroundStyle(CueTheme.ink)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                    HStack(spacing: 12) {
                        compactMetric(value: "\(Int(session.averageWPM))", label: "WPM")
                        compactMetric(value: "\(session.fillerCount)", label: "FILLERS")
                        compactMetric(value: session.durationSeconds.clockString, label: "TIME")
                    }
                }
            }
        }
        .buttonStyle(SpringPressStyle())
    }

    private func compactMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 23, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(CueTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyHistory: some View {
        PremiumCard(padding: 22) {
            HStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 24, weight: .ultraLight))
                    .foregroundStyle(CueTheme.violet)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your first baseline starts here")
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                    Text("Complete one session to unlock real trends and coaching.")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                }
            }
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(CueTheme.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Raw audio is never saved")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CueTheme.ink)
                Text("Session history keeps transcript, metrics, cue and checkpoint outcomes, and generated coaching—not audio.")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
            }
        }
        .padding(.horizontal, 4)
    }

    private var connectionColor: Color {
        if case .ready = model.connectionState { return CueTheme.green }
        if case .reconnecting = model.connectionState { return CueTheme.amber }
        return CueTheme.secondaryInk
    }

    private var connectionSymbol: String {
        if case .ready = model.connectionState { return "checkmark.circle.fill" }
        if case .reconnecting = model.connectionState { return "arrow.triangle.2.circlepath" }
        return "applewatch.slash"
    }
}

extension TimeInterval {
    var clockString: String {
        let total = max(0, Int(self.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
