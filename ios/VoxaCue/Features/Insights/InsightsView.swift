import SwiftUI
import VoxaCore

struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window: InsightWindow = .all
    @State private var showingProPaywall = false
    @State private var pendingRoadmapSession: SessionSummary?
    @State private var confirmingRoadmap = false
    @State private var confirmingCoach = false
    @State private var showingRoadmap = false
    @State private var showingCoach = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueTheme.Space.large) {
                Text("Insights")
                    .font(.cueTitle)
                    .foregroundStyle(CueTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                if model.demoMode {
                    StatusPill(
                        label: "Deterministic demo data",
                        symbol: "testtube.2",
                        color: CueTheme.amber
                    )
                }
                if model.sessions.isEmpty {
                    emptyState
                } else if !model.proEntitlementStore.hasProAccess {
                    ProInsightsGateCard {
                        showingProPaywall = true
                    }
                } else {
                    windowPicker
                    practiceRoadmapCard
                    if filteredSessions.isEmpty {
                        rangeEmptyState
                    } else {
                        trendCard
                        metricsGrid
                        voiceAndRhythmCard
                        measurementCoverageCard
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
        .sheet(isPresented: $showingProPaywall) {
            VoxaProPaywallView(entitlementStore: model.proEntitlementStore)
        }
        .navigationDestination(isPresented: $showingRoadmap) {
            if let snapshot = model.practiceRoadmap {
                RoadmapView(
                    snapshot: snapshot,
                    sourceSessionName: roadmapSourceSession?.name ?? "Practice session",
                    isDemoMode: model.demoMode,
                    coachAvailable: roadmapCanBeRequested,
                    askCoachAction: requestCoachConsent
                )
            }
        }
        .sheet(isPresented: $showingCoach, onDismiss: clearTransientCoachConversation) {
            if let snapshot = model.practiceRoadmap {
                CoachChatView(
                    snapshot: snapshot,
                    sourceSessionName: roadmapSourceSession?.name ?? "Practice session",
                    isDemoMode: model.demoMode
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog(
            roadmapConfirmationTitle,
            isPresented: $confirmingRoadmap,
            titleVisibility: .visible
        ) {
            Button(model.practiceRoadmap == nil ? "Build roadmap" : "Refresh roadmap") {
                guard let session = pendingRoadmapSession else { return }
                pendingRoadmapSession = nil
                Task { await model.generateRoadmap(for: session) }
            }
            Button("Cancel", role: .cancel) {
                pendingRoadmapSession = nil
            }
        } message: {
            Text(roadmapConsentCopy)
        }
        .confirmationDialog(
            model.demoMode ? "Open demo coach?" : "Ask Cue about this session?",
            isPresented: $confirmingCoach,
            titleVisibility: .visible
        ) {
            Button(model.demoMode ? "Open demo coach" : "Share context and continue") {
                model.clearCoachConversation()
                showingCoach = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(coachConsentCopy)
        }
        .animation(CueMotion.settle(reduceMotion: reduceMotion), value: model.isGeneratingRoadmap)
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
                value: "\(Int(analytics.averageWPM.rounded()))",
                detail: "WPM",
                tint: CueTheme.signal
            )
            MetricTile(
                label: "Filler rate",
                value: String(format: "%.1f", analytics.fillersPerSpeakingMinute),
                detail: "per speaking min",
                tint: analytics.fillersPerSpeakingMinute <= 2 ? CueTheme.green : CueTheme.amber
            )
            MetricTile(
                label: TimingOutcome.onTarget.presentation.aggregateLabel,
                value: "\(Int((analytics.onTargetSessionRatio * 100).rounded()))%",
                detail: "of sessions",
                tint: TimingOutcome.onTarget.presentation.tint
            )
            MetricTile(
                label: "Talk ratio",
                value: "\(Int((analytics.talkRatio * 100).rounded()))%",
                detail: "active speech",
                tint: CueTheme.signal
            )
        }
    }

    private var voiceAndRhythmCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    CueSectionLabel(text: "Voice and rhythm", color: CueTheme.signal)
                    Spacer()
                    StatusPill(
                        label: "On-device",
                        symbol: "iphone",
                        color: CueTheme.green
                    )
                }
                CueMetricGrid(spacing: 12) {
                    compactMetric(
                        label: "Intonation span",
                        value: analytics.averagePitchRangeSemitones.map { String(format: "%.1f st", $0) },
                        fallback: "Not measured"
                    )
                    compactMetric(
                        label: "Pace variability",
                        value: analytics.averagePaceStandardDeviationWPM.map { String(format: "%.0f WPM", $0) },
                        fallback: "Not measured"
                    )
                    compactMetric(
                        label: "Internal pauses",
                        value: analytics.pausesPerPresentationMinute.map { String(format: "%.1f/min", $0) },
                        fallback: "Not measured"
                    )
                    compactMetric(
                        label: "Average pause",
                        value: analytics.averagePauseSeconds.map { String(format: "%.1f sec", $0) },
                        fallback: "Not measured"
                    )
                }
                Text("Measurements, not a voice score.")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var measurementCoverageCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                CueSectionLabel(text: "Measurement coverage", color: CueTheme.secondaryInk)
                CueMetricGrid(spacing: 12) {
                    coverageValue(
                        value: "\(analytics.sessionCount)",
                        label: "sessions"
                    )
                    coverageValue(
                        value: "\(Int((analytics.totalPresentationSeconds / 60).rounded()))",
                        label: "minutes"
                    )
                    coverageValue(
                        value: "\(analytics.measuredIntonationSessionCount)",
                        label: "measured sessions"
                    )
                }
                HStack {
                    Label(
                        "Average finish deviation",
                        systemImage: "timer"
                    )
                    Spacer()
                    Text("\(Int(analytics.averageAbsoluteTimingDeviationSeconds.rounded())) sec")
                        .monospacedDigit()
                }
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
            }
        }
    }

    private func compactMetric(label: String, value: String?, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value ?? fallback)
                .font(.system(.title3, design: .rounded, weight: .medium).monospacedDigit())
                .foregroundStyle(value == nil ? CueTheme.secondaryInk : CueTheme.ink)
            Text(label)
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(14)
        .background(CueTheme.canvas.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func coverageValue(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .medium).monospacedDigit())
                .foregroundStyle(CueTheme.ink)
            Text(label)
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    }

    @ViewBuilder
    private var practiceRoadmapCard: some View {
        if let snapshot = model.practiceRoadmap {
            generatedRoadmapCard(snapshot)
        } else {
            roadmapPromptCard
        }
    }

    private func generatedRoadmapCard(_ snapshot: SavedPracticeRoadmap) -> some View {
        HeroCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Label("Practice roadmap", systemImage: "map")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.signal)
                    Spacer(minLength: 8)
                    if model.isGeneratingRoadmap {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CueTheme.signal)
                            .accessibilityLabel("Refreshing roadmap")
                    } else {
                        Menu {
                            Button("Refresh roadmap", systemImage: "arrow.clockwise") {
                                requestRoadmapConsent()
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CueTheme.secondaryInk)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Roadmap actions")
                        .disabled(!roadmapCanBeRequested)
                        .opacity(roadmapCanBeRequested ? 1 : 0.46)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(snapshot.roadmap.headline)
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(snapshot.roadmap.summary)
                        .font(.cueBody)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .lineLimit(3)
                        .lineSpacing(3)
                }

                if let filler = snapshot.roadmap.focusFillers.first {
                    HStack(spacing: 9) {
                        Image(systemName: "quote.bubble")
                            .foregroundStyle(CueTheme.haptic)
                            .accessibilityHidden(true)
                        Text("Focus: “\(filler.phrase)” · \(filler.count)×")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(CueTheme.ink)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(CueTheme.haptic.opacity(0.10))
                    .clipShape(Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Focus phrase \(filler.phrase), detected \(filler.count) times")
                }

                if let step = snapshot.roadmap.steps.first(where: { $0.phase == .now }) {
                    VStack(alignment: .leading, spacing: 5) {
                        CueSectionLabel(text: "Now", color: CueTheme.signal)
                        Text(step.title)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(CueTheme.ink)
                        Text(step.action)
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(CueTheme.signalSoft.opacity(0.66))
                    .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.small, style: .continuous))
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        roadmapActionButton(
                            title: "View roadmap",
                            symbol: "arrow.right",
                            filled: true,
                            disabled: false,
                            action: { showingRoadmap = true }
                        )
                        roadmapActionButton(
                            title: "Ask Cue",
                            symbol: "message",
                            filled: false,
                            disabled: !roadmapCanBeRequested,
                            action: requestCoachConsent
                        )
                    }
                    VStack(spacing: 10) {
                        roadmapActionButton(
                            title: "View roadmap",
                            symbol: "arrow.right",
                            filled: true,
                            disabled: false,
                            action: { showingRoadmap = true }
                        )
                        roadmapActionButton(
                            title: "Ask Cue",
                            symbol: "message",
                            filled: false,
                            disabled: !roadmapCanBeRequested,
                            action: requestCoachConsent
                        )
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: model.demoMode ? "testtube.2" : "lock.shield")
                    Text(model.demoMode ? "Deterministic demo" : "Based on \(roadmapSourceSession?.name ?? "one selected session")")
                }
                .font(.cueCaption)
                .foregroundStyle(model.demoMode ? CueTheme.amber : CueTheme.secondaryInk)
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
    }

    private var roadmapPromptCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Practice roadmap", systemImage: "map")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.signal)
                Text("Know what to practice next")
                    .font(.cueSection)
                    .foregroundStyle(CueTheme.ink)
                Text(roadmapAvailabilityCopy)
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(3)

                if roadmapCanBeRequested, latestTranscriptSession != nil {
                    VoxaAsyncButton(
                        title: model.demoMode ? "Build demo roadmap" : "Build my roadmap",
                        loadingTitle: "Building roadmap…",
                        symbol: "arrow.right",
                        isLoading: model.isGeneratingRoadmap,
                        action: requestRoadmapConsent
                    )
                } else if latestTranscriptSession == nil {
                    StatusPill(
                        label: "A finalized transcript is required",
                        symbol: "text.quote",
                        color: CueTheme.secondaryInk
                    )
                } else {
                    StatusPill(
                        label: "Coaching service not configured",
                        symbol: "lock",
                        color: CueTheme.secondaryInk
                    )
                }
            }
        }
    }

    private func roadmapActionButton(
        title: String,
        symbol: String,
        filled: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(filled ? Color.white : CueTheme.signal)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 15)
            .background(filled ? CueTheme.actionFill : CueTheme.signalSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(SpringPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.46 : 1)
        .accessibilityLabel(title)
    }

    private var roadmapAvailabilityCopy: String {
        if model.demoMode {
            return "Preview a labeled roadmap without sending data."
        }
        if !roadmapCanBeRequested {
            return "Your measurements remain available on this iPhone."
        }
        return "Use one transcript and your measured trends to build a focused plan."
    }

    private var roadmapCanBeRequested: Bool {
        if model.demoMode { return true }
        if case .localOnly = model.coachingAPIState { return false }
        return true
    }

    private var latestTranscriptSession: SessionSummary? {
        model.sessions.first { session in
            !session.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var roadmapSourceSession: SessionSummary? {
        guard let sourceSessionID = model.practiceRoadmap?.sourceSessionID else { return nil }
        return model.sessions.first { $0.sessionID == sourceSessionID }
    }

    private var roadmapConfirmationTitle: String {
        if model.demoMode { return "Build demo roadmap?" }
        return model.practiceRoadmap == nil ? "Build your roadmap?" : "Refresh your roadmap?"
    }

    private var roadmapConsentCopy: String {
        if model.demoMode {
            return "This uses a deterministic roadmap fixture. No session data leaves the phone."
        }
        let sessionName = pendingRoadmapSession?.name ?? "the selected session"
        return "Voxa Cue sends exactly one finalized transcript (\(sessionName)), on-device aggregate history, and deterministic filler counts. Prior transcript text and raw audio stay on this iPhone."
    }

    private var coachConsentCopy: String {
        if model.demoMode {
            return "This opens a deterministic coach fixture. No session data leaves the phone."
        }
        let sessionName = roadmapSourceSession?.name ?? "the selected session"
        return "Voxa Cue sends \(sessionName)’s finalized transcript, this roadmap, measured session metrics, and the messages you type. Raw audio and other transcript text stay on this iPhone."
    }

    private func requestRoadmapConsent() {
        guard let session = latestTranscriptSession, roadmapCanBeRequested else { return }
        pendingRoadmapSession = session
        confirmingRoadmap = true
    }

    private func requestCoachConsent() {
        guard roadmapSourceSession != nil, roadmapCanBeRequested else { return }
        confirmingCoach = true
    }

    private func clearTransientCoachConversation() {
        model.clearCoachConversation()
        Task { @MainActor in
            while model.isSendingCoachMessage {
                try? await Task.sleep(for: .milliseconds(100))
            }
            model.clearCoachConversation()
        }
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
                                .lineLimit(2)
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
                Text("Compare pace, fillers, timing, and talk ratio.")
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

    private var averagePaceRange: Double {
        analytics.timeInPaceRange
    }

    private var analytics: LongTermAnalytics {
        makeLongTermAnalytics(sessions: orderedSessions)
    }

    private var paceTrend: Double? {
        guard orderedSessions.count >= 6 else { return nil }
        let comparison = Array(orderedSessions.suffix(6))
        let previous = Array(comparison.prefix(3))
        let recent = Array(comparison.suffix(3))
        return weightedPaceRange(recent) - weightedPaceRange(previous)
    }

    private var paceTrendLabel: String {
        guard let paceTrend else { return "Building baseline" }
        let points = Int(abs(paceTrend * 100).rounded())
        if points == 0 { return "Steady" }
        return paceTrend > 0 ? "+\(points) pts" : "−\(points) pts"
    }

    private var paceTrendSymbol: String {
        guard let paceTrend else { return "circle.dotted" }
        if paceTrend > 0 { return "arrow.up.right" }
        if paceTrend < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var paceTrendColor: Color {
        guard let paceTrend else { return CueTheme.secondaryInk }
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

    private func weightedPaceRange(_ sessions: [SessionSummary]) -> Double {
        let duration = sessions.reduce(0) { $0 + max(0, $1.durationSeconds) }
        guard duration > 0 else { return 0 }
        return sessions.reduce(0) { partial, session in
            partial + session.timeInPaceRange * max(0, session.durationSeconds)
        } / duration
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
