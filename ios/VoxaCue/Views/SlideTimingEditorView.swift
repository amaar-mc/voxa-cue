import SwiftUI
import VoxaCore

struct SlideTimingEditorView: View {
    let slides: [DeckSlide]
    @Binding var durationsSeconds: [Int]
    let targetDurationSeconds: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                totalCard
                VStack(spacing: 12) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        slideRow(index: index, slide: slide)
                    }
                }
                Button("Reset evenly") {
                    resetEvenly()
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CueTheme.signal)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
        }
        .background(CueTheme.canvas)
        .navigationTitle("Slide timing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var totalCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                CueSectionLabel(text: "Allotted time", color: totalsMatch ? CueTheme.green : CueTheme.red)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(assignedTotal.clockString)
                            .font(.cueSection.monospacedDigit())
                            .foregroundStyle(CueTheme.ink)
                        Text("assigned of \(TimeInterval(targetDurationSeconds).clockString)")
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(assignedTotal.clockString)
                            .font(.cueSection.monospacedDigit())
                            .foregroundStyle(CueTheme.ink)
                        Text("assigned of \(TimeInterval(targetDurationSeconds).clockString)")
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                }
                Label(
                    totalsMatch ? "Ready" : totalAdjustmentMessage,
                    systemImage: totalsMatch ? "checkmark.circle.fill" : "arrow.left.arrow.right"
                )
                .font(.cueCaption.weight(.semibold))
                .foregroundStyle(totalsMatch ? CueTheme.green : CueTheme.red)
            }
        }
    }

    private func slideRow(index: Int, slide: DeckSlide) -> some View {
        PremiumCard(padding: 16) {
            Stepper(
                value: durationBinding(index: index),
                in: 1...max(1, targetDurationSeconds),
                step: 5
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        slideIdentity(index: index, slide: slide)
                        Spacer(minLength: 8)
                        Text(TimeInterval(duration(at: index)).clockString)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(CueTheme.signal)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        slideIdentity(index: index, slide: slide)
                        Text(TimeInterval(duration(at: index)).clockString)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(CueTheme.signal)
                    }
                }
            }
            .accessibilityLabel("Slide \(index + 1), \(slide.title)")
            .accessibilityValue("\(duration(at: index)) seconds")
        }
    }

    private func slideIdentity(index: Int, slide: DeckSlide) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Slide \(index + 1)")
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
            Text(slide.title.isEmpty ? "Untitled slide" : slide.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CueTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
    }

    private var assignedTotal: TimeInterval {
        TimeInterval(durationsSeconds.reduce(0, +))
    }

    private var totalsMatch: Bool {
        Int(assignedTotal) == targetDurationSeconds
    }

    private var totalAdjustmentMessage: String {
        let difference = targetDurationSeconds - Int(assignedTotal)
        return difference > 0
            ? "Add \(TimeInterval(difference).clockString)"
            : "Remove \(TimeInterval(abs(difference)).clockString)"
    }

    private func duration(at index: Int) -> Int {
        guard durationsSeconds.indices.contains(index) else { return 1 }
        return durationsSeconds[index]
    }

    private func durationBinding(index: Int) -> Binding<Int> {
        Binding(
            get: { duration(at: index) },
            set: { value in
                guard durationsSeconds.indices.contains(index) else { return }
                durationsSeconds[index] = value
            }
        )
    }

    private func resetEvenly() {
        guard !slides.isEmpty else { return }
        let base = targetDurationSeconds / slides.count
        let remainder = targetDurationSeconds % slides.count
        durationsSeconds = slides.indices.map { index in
            base + (index < remainder ? 1 : 0)
        }
    }
}
