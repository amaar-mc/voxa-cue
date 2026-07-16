import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var hasCompletedOnboarding: Bool
    @State private var page = 0

    private let pages = [
        OnboardingPage(
            eyebrow: "Meet Voxa Cue",
            title: "Discreet guidance.\nConfident delivery.",
            body: "Your iPhone listens while you present. The band delivers private cues.",
            assetName: "VoiceSignal"
        ),
        OnboardingPage(
            eyebrow: "Private by design",
            title: "Live coaching stays\non your iPhone.",
            body: "Transcription, pace, fillers, and timing stay on-device. Raw audio is never saved.",
            assetName: "OnDevicePrivacy"
        ),
        OnboardingPage(
            eyebrow: "Connect the band",
            title: "Learn the language\nof each cue.",
            body: "Pair the band for wrist feedback, or continue with phone-only analytics.",
            assetName: "HapticBand"
        )
    ]

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(CueMotion.settle(reduceMotion: reduceMotion), value: page)

                footer
            }
        }
    }

    private var background: some View {
        CueTheme.canvas.ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            CueWordmark(compact: false)
            Spacer()
            Text("\(page + 1) of \(pages.count)")
                .font(.cueCaption.monospacedDigit())
                .foregroundStyle(CueTheme.secondaryInk)
                .accessibilityLabel("Page \(page + 1) of \(pages.count)")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? CueTheme.signal : CueTheme.border)
                        .frame(width: index == page ? 25 : 7, height: 7)
                        .animation(CueMotion.quick(reduceMotion: reduceMotion), value: page)
                }
            }
            .accessibilityHidden(true)

            if page == 2 {
                bandPairingFooter
            } else {
                VoxaButton(
                    title: page == pages.count - 1 ? "Start coaching" : "Continue",
                    symbol: page == pages.count - 1 ? "arrow.right" : "chevron.right",
                    style: .primary,
                    disabled: false,
                    action: advance
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var bandPairingFooter: some View {
        VStack(spacing: 10) {
            StatusPill(label: model.connectionState.label, symbol: bandStatusSymbol, color: bandStatusColor)

            VoxaButton(
                title: bandButtonTitle,
                symbol: bandIsReady ? "checkmark" : "wave.3.right",
                style: .primary,
                disabled: bandIsBusy,
                action: bandPrimaryAction
            )

            Button("Continue with analytics only", action: advance)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CueTheme.secondaryInk)
                .frame(minHeight: 44)
                .buttonStyle(SpringPressStyle())
                .accessibilityHint("You can connect the Cue Band later in Settings")
        }
    }

    private var bandIsReady: Bool {
        if case .ready = model.connectionState { return true }
        return false
    }

    private var bandIsBusy: Bool {
        switch model.connectionState {
        case .searching, .connecting, .discovering, .reconnecting: true
        default: false
        }
    }

    private var bandButtonTitle: String {
        if bandIsReady { return "Start with Cue Band" }
        if bandIsBusy { return "Searching for Cue Band…" }
        return "Connect Cue Band"
    }

    private var bandStatusSymbol: String {
        if bandIsReady { return "checkmark.circle.fill" }
        if bandIsBusy { return "antenna.radiowaves.left.and.right" }
        if case .failed = model.connectionState { return "exclamationmark.triangle.fill" }
        return "applewatch"
    }

    private var bandStatusColor: Color {
        if bandIsReady { return CueTheme.green }
        if bandIsBusy { return CueTheme.signal }
        if case .failed = model.connectionState { return CueTheme.red }
        return CueTheme.secondaryInk
    }

    private func bandPrimaryAction() {
        if bandIsReady {
            advance()
        } else {
            model.connectCueBand()
        }
    }

    private func advance() {
        if page < pages.count - 1 {
            withAnimation(CueMotion.settle(reduceMotion: reduceMotion)) {
                page += 1
            }
        } else {
            hasCompletedOnboarding = true
        }
    }
}

private struct OnboardingPage: Hashable {
    let eyebrow: String
    let title: String
    let body: String
    let assetName: String
}

private struct OnboardingPageView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 34)
                PremiumCard(padding: dynamicTypeSize.isAccessibilitySize ? 16 : 24) {
                    SectionMark(
                        assetName: page.assetName,
                        size: dynamicTypeSize.isAccessibilitySize ? 116 : 176
                    )
                        .frame(maxWidth: .infinity)
                }
                CueSectionLabel(text: page.eyebrow, color: CueTheme.signal)
                Text(page.title)
                    .font(.cueHero)
                    .foregroundStyle(CueTheme.ink)
                    .lineSpacing(-1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.body)
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
    }
}
