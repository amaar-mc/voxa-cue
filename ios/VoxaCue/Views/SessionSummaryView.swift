import SwiftUI
import VoxaCore

struct SessionSummaryView: View {
    @Environment(AppModel.self) private var model
    let summary: SessionSummary
    let dismissAction: () -> Void
    @State private var confirmAI = false
    @State private var transcriptExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let evidenceDisclosure = summaryEvidenceDisclosure(isDemoMode: model.demoMode) {
                        StatusPill(
                            label: evidenceDisclosure,
                            symbol: "testtube.2",
                            color: CueTheme.amber
                        )
                    }
                    hero
                    metricsGrid
                    vocalCard
                    coachingCard
                    transcriptCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
            .background(CueTheme.canvas)
            .navigationTitle("Session summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismissAction)
                }
            }
            .confirmationDialog(
                model.demoMode ? "Generate demo coaching?" : "Generate AI coaching?",
                isPresented: $confirmAI,
                titleVisibility: .visible
            ) {
                Button(model.demoMode ? "Generate demo coaching" : "Send coaching context") {
                    Task { await model.generateInsight(for: summary) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    model.demoMode
                        ? "This uses a deterministic coaching fixture. No session data leaves the phone."
                        : "This sends the final transcript, aggregate metrics, cue delivery history, and checkpoint outcomes to the Voxa Cue API. Raw audio never leaves the phone."
                )
            }
        }
    }

    private var hero: some View {
        PremiumCard(padding: 22) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(timingPresentation.tint.opacity(0.12))
                    Image(systemName: timingPresentation.symbol)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(timingPresentation.tint)
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(timingPresentation.title)
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                    Text(summary.name)
                        .font(.cueBody)
                        .foregroundStyle(CueTheme.secondaryInk)
                    Text("\(summary.durationSeconds.clockString) of \(summary.targetDurationSeconds.clockString)")
                        .font(.cueCaption.monospacedDigit())
                        .foregroundStyle(timingPresentation.tint)
                }
                Spacer()
            }
        }
    }

    private var metricsGrid: some View {
        CueMetricGrid(spacing: 12) {
            MetricTile(
                label: "Average pace",
                value: "\(Int(summary.averageWPM.rounded()))",
                detail: "WPM",
                tint: CueTheme.signal
            )
            MetricTile(
                label: "In target",
                value: "\(Int(summary.timeInPaceRange * 100))%",
                detail: "of sampled time",
                tint: CueTheme.green
            )
            MetricTile(
                label: "Fillers",
                value: "\(summary.fillerCount)",
                detail: String(format: "%.1f per speaking min", summary.fillersPerSpeakingMinute),
                tint: summary.fillersPerSpeakingMinute <= 2 ? CueTheme.green : CueTheme.amber
            )
            MetricTile(
                label: "Talk ratio",
                value: "\(Int(summary.talkRatio * 100))%",
                detail: "active speech",
                tint: CueTheme.signal
            )
            MetricTile(
                label: "Cues confirmed",
                value: "\(summary.cueCount)",
                detail: "accepted or completed",
                tint: CueTheme.green
            )
            MetricTile(
                label: "Timing",
                value: timingDelta,
                detail: timingPresentation.metricDetail,
                tint: timingPresentation.tint
            )
        }
    }

    private var vocalCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 17) {
                CueSectionLabel(text: "Vocal delivery", color: CueTheme.signal)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        vocalMetrics
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        vocalMetrics
                    }
                }
                Text("These are descriptive acoustic ranges, not judgments about what a voice should sound like.")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
            }
        }
    }

    @ViewBuilder
    private var vocalMetrics: some View {
        vocalMetric(
            title: "Pitch range",
            value: summary.pitchRangeSemitones.map { String(format: "%.1f st", $0) } ?? "—",
            symbol: "waveform.path"
        )
        vocalMetric(
            title: "Energy range",
            value: summary.energyRangeDB.map { String(format: "%.1f dB", $0) } ?? "—",
            symbol: "speaker.wave.2"
        )
    }

    private func vocalMetric(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(CueTheme.signal)
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.system(.title3, design: .rounded, weight: .light).monospacedDigit())
                Text(title).font(.cueCaption).foregroundStyle(CueTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var coachingCard: some View {
        if let insight = model.insightBySession[summary.sessionID] {
            PremiumCard(padding: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Label("Personalized coaching", systemImage: "sparkles")
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.signal)
                            Spacer()
                            coachingSourcePill
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Personalized coaching", systemImage: "sparkles")
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.signal)
                            coachingSourcePill
                        }
                    }
                    Text(insight.overallSummary)
                        .font(.cueBody)
                        .foregroundStyle(CueTheme.ink)
                        .lineSpacing(4)
                    Divider().overlay(CueTheme.border)
                    VStack(alignment: .leading, spacing: 11) {
                        CueSectionLabel(text: "Strengths", color: CueTheme.green)
                        ForEach(insight.strengths) { strength in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(CueTheme.green)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(strength.title)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    Text(strength.evidence)
                                        .font(.cueCaption)
                                        .foregroundStyle(CueTheme.secondaryInk)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 11) {
                        CueSectionLabel(text: "Next priorities", color: CueTheme.signal)
                        ForEach(insight.priorities) { priority in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(priority.title)
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                Text(priority.evidence)
                                    .font(.cueCaption)
                                    .foregroundStyle(CueTheme.secondaryInk)
                                Label(priority.nextAction, systemImage: "arrow.turn.down.right")
                                    .font(.cueCaption)
                                    .foregroundStyle(CueTheme.signal)
                            }
                            .padding(15)
                            .background(CueTheme.signalSoft.opacity(0.62))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    VStack(alignment: .leading, spacing: 11) {
                        CueSectionLabel(text: "Practice drills", color: CueTheme.signal)
                        ForEach(insight.drills) { drill in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(drill.title)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    Spacer()
                                    Text("\(drill.durationMinutes) min")
                                        .font(.cueCaption.monospacedDigit())
                                        .foregroundStyle(CueTheme.secondaryInk)
                                }
                                Text(drill.instructions)
                                    .font(.cueCaption)
                                    .foregroundStyle(CueTheme.secondaryInk)
                            }
                        }
                    }
                    Text(insight.confidenceNote)
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                }
            }
        } else {
            PremiumCard(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Personalized coaching", systemImage: "sparkles")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.signal)
                    Text("Turn this session into an evidence-backed practice plan.")
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                    Text(
                        model.demoMode
                            ? "Demo mode returns a labeled deterministic coaching fixture without a network request."
                            : coachingCanBeRequested
                                ? "Only the final transcript, aggregate metrics, cue delivery history, and checkpoint outcomes are sent after you confirm."
                                : "Live coaching and this session summary stay available locally. AI practice plans require a configured coaching service."
                    )
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                    if coachingCanBeRequested {
                        VoxaButton(
                            title: model.isGeneratingInsight
                                ? "Generating coaching…"
                                : (model.demoMode ? "Generate demo coaching" : "Generate AI coaching"),
                            symbol: "sparkles",
                            style: .secondary,
                            disabled: model.isGeneratingInsight || summary.transcript.isEmpty,
                            action: { confirmAI = true }
                        )
                        if summary.transcript.isEmpty {
                            Label("A finalized transcript is required for AI coaching.", systemImage: "info.circle")
                                .font(.cueCaption)
                                .foregroundStyle(CueTheme.secondaryInk)
                        }
                    } else {
                        StatusPill(
                            label: "Local coaching only",
                            symbol: "iphone",
                            color: CueTheme.secondaryInk
                        )
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

    private var coachingCanBeRequested: Bool {
        if model.demoMode { return true }
        if case .localOnly = model.coachingAPIState { return false }
        return true
    }

    private var transcriptCard: some View {
        PremiumCard(padding: 20) {
            DisclosureGroup(isExpanded: $transcriptExpanded) {
                Text(summary.transcript.isEmpty ? "No finalized transcript was available." : summary.transcript)
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(4)
                    .padding(.top, 14)
                    .textSelection(.enabled)
            } label: {
                Label("Transcript", systemImage: "text.quote")
                    .font(.cueSection)
                    .foregroundStyle(CueTheme.ink)
            }
            .tint(CueTheme.signal)
        }
    }

    private var timingPresentation: TimingOutcomePresentation {
        summary.timingOutcome.presentation
    }

    private var timingDelta: String {
        abs(summary.targetDurationSeconds - summary.durationSeconds).clockString
    }
}

func summaryEvidenceDisclosure(isDemoMode: Bool) -> String? {
    isDemoMode ? "Deterministic demo data" : nil
}
