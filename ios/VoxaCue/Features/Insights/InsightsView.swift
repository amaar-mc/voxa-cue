import SwiftUI
import VoxaCore

struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @State private var window: InsightWindow = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueTheme.Space.large) {
                ScreenTitle(
                    eyebrow: "Long-term coaching",
                    title: "Insights",
                    subtitle: "Track what is changing across rehearsals and choose the next habit to practice."
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
                    windowPicker
                    if filteredSessions.isEmpty {
                        rangeEmptyState
                    } else {
                        trendCard
                        metricsGrid
                        coachingFocus
                        recentSessions
                    }
                }
            }
            .padding(.horizontal, CueTheme.Space.large)
            .padding(.top, CueTheme.Space.medium)
            .padding(.bottom, 36)
        }
        .background(CueTheme.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var windowPicker: some View {
        Picker("Insight range", selection: $window) {
            ForEach(InsightWindow.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Insight date range")
    }

    private var trendCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        CueSectionLabel(text: "Pace consistency", color: CueTheme.signal)
                        Text("\(Int((averagePaceRange * 100).rounded()))%")
                            .font(.cueMetric)
                            .foregroundStyle(CueTheme.ink)
                        Text("average sampled time in target range")
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                    Spacer()
                    StatusPill(
                        label: paceTrendLabel,
                        symbol: paceTrendSymbol,
                        color: paceTrendColor
                    )
                }
                SessionSparkline(
                    values: orderedSessions.map(\.timeInPaceRange),
                    lineColor: CueTheme.signal,
                    fillColor: CueTheme.signalSoft
                )
                .frame(height: 92)
                .accessibilityLabel("Pace consistency trend")
                .accessibilityValue(paceTrendAccessibilityValue)
            }
        }
    }

    private var metricsGrid: some View {
        CueMetricGrid(spacing: 12) {
            MetricTile(
                label: "Average pace",
                value: "\(Int(averageWPM.rounded()))",
                detail: "WPM",
                tint: CueTheme.signal
            )
            MetricTile(
                label: "Filler rate",
                value: String(format: "%.1f", averageFillersPerSpeakingMinute),
                detail: "per speaking min",
                tint: averageFillersPerSpeakingMinute <= 2 ? CueTheme.green : CueTheme.amber
            )
            MetricTile(
                label: TimingOutcome.onTarget.presentation.aggregateLabel,
                value: "\(Int((onTargetRatio * 100).rounded()))%",
                detail: "of sessions",
                tint: TimingOutcome.onTarget.presentation.tint
            )
            MetricTile(
                label: "Talk ratio",
                value: "\(Int((averageTalkRatio * 100).rounded()))%",
                detail: "active speech",
                tint: CueTheme.signal
            )
        }
    }

    @ViewBuilder
    private var coachingFocus: some View {
        if let selection = latestInsight {
            PremiumCard(padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Label("Next practice focus", systemImage: "sparkles")
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.signal)
                            Spacer()
                            coachingSourcePill
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Next practice focus", systemImage: "sparkles")
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.signal)
                            coachingSourcePill
                        }
                    }
                    Text(selection.insight.priorities.first?.title ?? "Keep building your baseline")
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                    Text(selection.insight.priorities.first?.nextAction ?? selection.insight.overallSummary)
                        .font(.cueBody)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .lineSpacing(3)
                    Button {
                        model.selectedSummary = selection.session
                    } label: {
                        Label("Open \(selection.session.name)", systemImage: "arrow.up.right")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(CueTheme.signal)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SpringPressStyle())
                }
            }
        } else {
            PremiumCard(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Next practice focus", systemImage: "sparkles")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.signal)
                    Text("Turn a session into a focused drill")
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                    Text(coachingAvailabilityCopy)
                        .font(.cueBody)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .lineSpacing(3)
                    if let latest = model.sessions.first {
                        Button {
                            model.selectedSummary = latest
                        } label: {
                            Label("Open latest session", systemImage: "arrow.up.right")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(CueTheme.signal)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(SpringPressStyle())
                    }
                }
            }
        }
    }

    private var coachingSourcePill: some View {
        StatusPill(
            label: model.demoMode ? "Demo fixture" : "AI generated",
            symbol: model.demoMode ? "testtube.2" : "checkmark",
            color: model.demoMode ? CueTheme.amber : CueTheme.green
        )
    }

    private var coachingAvailabilityCopy: String {
        if model.demoMode {
            return "Open a session for a labeled coaching fixture. No data leaves the phone."
        }
        if !model.demoMode, case .localOnly = model.coachingAPIState {
            return "Session analytics stay local. Configure the coaching service for AI practice plans."
        }
        return "Open a session and choose Generate AI coaching. Nothing is sent until you confirm."
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            CueSectionLabel(text: "Session snapshots", color: CueTheme.secondaryInk)
                .padding(.horizontal, 3)
            ForEach(Array(filteredSessions.prefix(3)), id: \.sessionID) { session in
                Button {
                    model.selectedSummary = session
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.name)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(CueTheme.ink)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.secondaryInk)
                        }
                        Spacer()
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) {
                                sessionSnapshotMetrics(session)
                            }
                            VStack(alignment: .trailing, spacing: 7) {
                                sessionSnapshotMetrics(session)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CueTheme.secondaryInk.opacity(0.6))
                    }
                    .padding(17)
                    .background(CueTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous)
                            .stroke(CueTheme.border.opacity(0.72), lineWidth: 0.7)
                    }
                }
                .buttonStyle(SpringPressStyle())
            }
        }
    }

    @ViewBuilder
    private func sessionSnapshotMetrics(_ session: SessionSummary) -> some View {
        snapshotValue(
            value: "\(Int((session.timeInPaceRange * 100).rounded()))%",
            label: "In pace"
        )
        snapshotValue(
            value: String(format: "%.1f", session.fillersPerSpeakingMinute),
            label: "Fillers/min"
        )
    }

    private func snapshotValue(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .medium).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(CueTheme.secondaryInk)
        }
    }

    private var emptyState: some View {
        PremiumCard(padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                SectionMark(assetName: "DeliveryAnalytics", size: 76)
                Text("Your trends start after one session")
                    .font(.cueSection)
                    .foregroundStyle(CueTheme.ink)
                Text("After one session, compare pace, fillers, timing, and talk ratio.")
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

    private var rangeEmptyState: some View {
        PremiumCard(padding: 22) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(CueTheme.signal)
                    .frame(width: 42, height: 42)
                    .background(CueTheme.signalSoft.opacity(0.62))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("No sessions in the last 7 days")
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                    Text("Choose All sessions or record a new rehearsal.")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .lineSpacing(2)
                }
            }
        }
    }

    private var filteredSessions: [SessionSummary] {
        let sorted = model.sessions.sorted { $0.startedAt > $1.startedAt }
        switch window {
        case .all:
            return sorted
        case .lastSevenDays:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            return sorted.filter { $0.startedAt >= cutoff }
        }
    }

    private var orderedSessions: [SessionSummary] {
        filteredSessions.sorted { $0.startedAt < $1.startedAt }
    }

    private var averageWPM: Double {
        average(orderedSessions.map(\.averageWPM))
    }

    private var averagePaceRange: Double {
        average(orderedSessions.map(\.timeInPaceRange))
    }

    private var averageFillersPerSpeakingMinute: Double {
        average(orderedSessions.map(\.fillersPerSpeakingMinute))
    }

    private var averageTalkRatio: Double {
        average(orderedSessions.map(\.talkRatio))
    }

    private var onTargetRatio: Double {
        guard !orderedSessions.isEmpty else { return 0 }
        let onTarget = orderedSessions.filter { $0.timingOutcome == .onTarget }.count
        return Double(onTarget) / Double(orderedSessions.count)
    }

    private var paceTrend: Double {
        guard let first = orderedSessions.first, let last = orderedSessions.last else { return 0 }
        return last.timeInPaceRange - first.timeInPaceRange
    }

    private var paceTrendLabel: String {
        guard orderedSessions.count > 1 else { return "Baseline" }
        let points = Int(abs(paceTrend * 100).rounded())
        if points == 0 { return "Steady" }
        return paceTrend > 0 ? "+\(points) pts" : "−\(points) pts"
    }

    private var paceTrendSymbol: String {
        guard orderedSessions.count > 1 else { return "scope" }
        if paceTrend > 0 { return "arrow.up.right" }
        if paceTrend < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var paceTrendColor: Color {
        guard orderedSessions.count > 1 else { return CueTheme.signal }
        if paceTrend > 0 { return CueTheme.green }
        if paceTrend < 0 { return CueTheme.amber }
        return CueTheme.secondaryInk
    }

    private var paceTrendAccessibilityValue: String {
        guard let first = orderedSessions.first, let last = orderedSessions.last else {
            return "No sessions"
        }
        let firstValue = Int((first.timeInPaceRange * 100).rounded())
        let lastValue = Int((last.timeInPaceRange * 100).rounded())
        return "\(orderedSessions.count) sessions, from \(firstValue) percent to \(lastValue) percent. \(paceTrendLabel)."
    }

    private var latestInsight: (session: SessionSummary, insight: CoachingInsight)? {
        for session in filteredSessions {
            if let insight = model.insightBySession[session.sessionID] {
                return (session, insight)
            }
        }
        return nil
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

private enum InsightWindow: String, CaseIterable, Identifiable {
    case lastSevenDays
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastSevenDays: "Last 7 days"
        case .all: "All sessions"
        }
    }
}

private struct SessionSparkline: View {
    let values: [Double]
    let lineColor: Color
    let fillColor: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack {
                ForEach([0.25, 0.50, 0.75], id: \.self) { ratio in
                    Path { path in
                        let y = proxy.size.height - (proxy.size.height * ratio)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(CueTheme.border.opacity(ratio == 0.75 ? 0.72 : 0.36), style: StrokeStyle(lineWidth: 0.7, dash: ratio == 0.75 ? [4, 4] : []))
                }
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    path.addLine(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [fillColor.opacity(0.52), fillColor.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(CueTheme.surface)
                        .stroke(lineColor, lineWidth: 2)
                        .frame(width: 8, height: 8)
                        .position(point)
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let horizontalInset = 5.0
        let verticalInset = 8.0
        return values.enumerated().map { index, value in
            let denominator = max(1, values.count - 1)
            let x = horizontalInset + (Double(index) / Double(denominator)) * max(0, size.width - horizontalInset * 2)
            let normalized = min(max(value, 0), 1)
            let y = size.height - verticalInset - normalized * max(0, size.height - verticalInset * 2)
            return CGPoint(x: x, y: y)
        }
    }
}
