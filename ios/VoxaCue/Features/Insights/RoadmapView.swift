import SwiftUI
import VoxaCore

struct RoadmapView: View {
    let snapshot: SavedPracticeRoadmap
    let sourceSessionName: String
    let isDemoMode: Bool
    let coachAvailable: Bool
    let askCoachAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueTheme.Space.large) {
                roadmapHeader
                nextSessionGoal

                if !snapshot.roadmap.focusFillers.isEmpty {
                    fillerFocus
                }

                VStack(alignment: .leading, spacing: 12) {
                    CueSectionLabel(text: "Your path", color: CueTheme.secondaryInk)
                        .padding(.horizontal, 3)
                    ForEach(Array(orderedSteps.enumerated()), id: \.element.id) { index, step in
                        roadmapStep(step, number: index + 1)
                    }
                }

                Button(action: askCoachAction) {
                    Label("Ask Cue about this plan", systemImage: "message")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CueTheme.signal)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(CueTheme.signalSoft)
                        .clipShape(Capsule())
                }
                .buttonStyle(SpringPressStyle())
                .disabled(!coachAvailable)
                .opacity(coachAvailable ? 1 : 0.46)

                Label(snapshot.roadmap.confidenceNote, systemImage: "info.circle")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, CueTheme.Space.large)
            .padding(.top, CueTheme.Space.medium)
            .padding(.bottom, 36)
        }
        .background(CueTheme.canvas)
        .navigationTitle("Practice roadmap")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roadmapHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusPill(
                label: isDemoMode ? "Deterministic demo" : "Based on \(sourceSessionName)",
                symbol: isDemoMode ? "testtube.2" : "lock.shield",
                color: isDemoMode ? CueTheme.amber : CueTheme.secondaryInk
            )
            Text(snapshot.roadmap.headline)
                .font(.cueTitle)
                .foregroundStyle(CueTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(snapshot.roadmap.summary)
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nextSessionGoal: some View {
        HeroCard(padding: 20) {
            VStack(alignment: .leading, spacing: 11) {
                Label("Next session", systemImage: "scope")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.signal)
                Text(snapshot.roadmap.nextSessionGoal.title)
                    .font(.cueSection)
                    .foregroundStyle(CueTheme.ink)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.roadmap.nextSessionGoal.measurement)
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                    Spacer(minLength: 8)
                    Text(snapshot.roadmap.nextSessionGoal.target)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(CueTheme.signal)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var fillerFocus: some View {
        VStack(alignment: .leading, spacing: 11) {
            CueSectionLabel(text: "Focus phrases", color: CueTheme.haptic)
            ForEach(Array(snapshot.roadmap.focusFillers.prefix(3))) { filler in
                VStack(alignment: .leading, spacing: 5) {
                    Text("“\(filler.phrase)” · \(filler.count)×")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(CueTheme.ink)
                    Text(filler.guidance)
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(CueTheme.haptic.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CueTheme.Radius.small, style: .continuous)
                        .stroke(CueTheme.haptic.opacity(0.16), lineWidth: 0.6)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func roadmapStep(_ step: RoadmapStep, number: Int) -> some View {
        PremiumCard(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                Text("\(number)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(CueTheme.signal)
                    .frame(width: 34, height: 34)
                    .background(CueTheme.signalSoft)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    CueSectionLabel(text: phaseLabel(step.phase), color: CueTheme.signal)
                    Text(step.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CueTheme.ink)
                    Text(step.evidence)
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .lineSpacing(2)
                    Label(step.action, systemImage: "arrow.turn.down.right")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.ink)
                        .lineSpacing(2)
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "scope")
                            .accessibilityHidden(true)
                        Text(step.measurableTarget)
                    }
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.signal)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(phaseLabel(step.phase)): \(step.title). \(step.action). Target: \(step.measurableTarget)")
    }

    private var orderedSteps: [RoadmapStep] {
        RoadmapPhase.allCases.compactMap { phase in
            snapshot.roadmap.steps.first { $0.phase == phase }
        }
    }

    private func phaseLabel(_ phase: RoadmapPhase) -> String {
        switch phase {
        case .now: "Now"
        case .next: "Next"
        case .then: "Then"
        }
    }
}
