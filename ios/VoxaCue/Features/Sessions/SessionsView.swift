import SwiftUI
import VoxaCore

struct SessionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueTheme.Space.large) {
                ScreenTitle(
                    eyebrow: "Practice history",
                    title: "Sessions",
                    subtitle: "Every rehearsal becomes a clearer baseline for your next one."
                )
                if model.demoMode {
                    StatusPill(
                        label: "Deterministic demo data",
                        symbol: "testtube.2",
                        color: CueTheme.amber
                    )
                }
                if model.sessions.isEmpty {
                    emptyState
                } else {
                    overview
                    sessionList
                }
            }
            .padding(.horizontal, CueTheme.Space.large)
            .padding(.top, CueTheme.Space.medium)
            .padding(.bottom, 36)
        }
        .background(CueTheme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.presentSessionSetup(intent: .freeSpeaking)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CueTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(CueTheme.surface)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(CueTheme.border.opacity(0.8), lineWidth: 0.7)
                        }
                }
                .accessibilityLabel("Start a new session")
            }
        }
    }

    private var overview: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        CueSectionLabel(text: "Your practice", color: CueTheme.signal)
                        Text(practiceHeadline)
                            .font(.cueSection)
                            .foregroundStyle(CueTheme.ink)
                    }
                    Spacer()
                    SectionMark(assetName: "SessionHistory", size: 54)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        overviewMetrics
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        overviewMetrics
                    }
                }
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            CueSectionLabel(text: "Recent sessions", color: CueTheme.secondaryInk)
                .padding(.horizontal, 3)
            ForEach(model.sessions, id: \.sessionID) { session in
                sessionRow(session)
            }
        }
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        Button {
            model.selectedSummary = session
        } label: {
            PremiumCard(padding: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(timingColor(for: session).opacity(0.11))
                            Image(systemName: timingSymbol(for: session))
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(timingColor(for: session))
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.name)
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(CueTheme.ink)
                                .lineLimit(2)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CueTheme.secondaryInk.opacity(0.65))
                            .padding(.top, 6)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            sessionRowMetrics(session)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            sessionRowMetrics(session)
                        }
                    }
                }
            }
        }
        .buttonStyle(SpringPressStyle())
        .accessibilityHint("Opens the session summary")
    }

    @ViewBuilder
    private var overviewMetrics: some View {
        overviewMetric(value: "\(model.sessions.count)", label: "Sessions")
        overviewMetric(value: totalPracticeTime, label: "Practice")
        overviewMetric(
            value: onTargetRate,
            label: TimingOutcome.onTarget.presentation.aggregateLabel
        )
    }

    @ViewBuilder
    private func sessionRowMetrics(_ session: SessionSummary) -> some View {
        rowMetric(
            value: "\(Int(session.averageWPM.rounded()))",
            label: "WPM",
            tint: CueTheme.signal
        )
        rowMetric(
            value: String(format: "%.1f", session.fillersPerSpeakingMinute),
            label: "Fillers/min",
            tint: session.fillersPerSpeakingMinute <= 2 ? CueTheme.green : CueTheme.amber
        )
        rowMetric(
            value: session.durationSeconds.clockString,
            label: "Duration",
            tint: timingColor(for: session)
        )
    }

    private func overviewMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .light).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(CueTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowMetric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.body, design: .rounded, weight: .light).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(CueTheme.secondaryInk)
            Capsule()
                .fill(tint.opacity(0.38))
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        PremiumCard(padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                SectionMark(assetName: "SessionHistory", size: 76)
                Text("Build your first baseline")
                    .font(.cueSection)
                    .foregroundStyle(CueTheme.ink)
                Text("Record one rehearsal to see your pace, fillers, timing, and vocal range.")
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(3)
                VoxaButton(
                    title: "Start a session",
                    symbol: "arrow.up.right",
                    style: .primary,
                    disabled: false,
                    action: { model.presentSessionSetup(intent: .freeSpeaking) }
                )
            }
        }
    }

    private var totalPracticeTime: String {
        let totalSeconds = model.sessions.reduce(0.0) { $0 + $1.durationSeconds }
        let totalMinutes = Int((totalSeconds / 60).rounded())
        return totalMinutes < 60 ? "\(totalMinutes)m" : String(format: "%.1fh", totalSeconds / 3_600)
    }

    private var practiceHeadline: String {
        switch model.sessions.count {
        case 1:
            "Your baseline is taking shape"
        case 2:
            "Your practice pattern is emerging"
        default:
            "A useful pattern is forming"
        }
    }

    private var onTargetRate: String {
        let onTargetCount = model.sessions.filter { $0.timingOutcome == .onTarget }.count
        let ratio = Double(onTargetCount) / Double(model.sessions.count)
        return "\(Int((ratio * 100).rounded()))%"
    }

    private func timingColor(for session: SessionSummary) -> Color {
        session.timingOutcome.presentation.tint
    }

    private func timingSymbol(for session: SessionSummary) -> String {
        session.timingOutcome.presentation.symbol
    }
}
