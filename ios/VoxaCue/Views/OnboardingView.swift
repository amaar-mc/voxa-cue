import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Binding var hasCompletedOnboarding: Bool
    @State private var page = 0

    private let pages = [
        OnboardingPage(
            eyebrow: "Meet Cue",
            title: "Your voice.\nPerfected.",
            body: "The phone listens while you present. Your Cue Band responds with private, eyes-free coaching.",
            symbol: "waveform.and.mic"
        ),
        OnboardingPage(
            eyebrow: "Private by design",
            title: "Fast coaching,\nwithout the cloud.",
            body: "Live transcription, pace, fillers, and timing run on your iPhone. Raw audio is never saved.",
            symbol: "iphone.gen3.radiowaves.left.and.right"
        ),
        OnboardingPage(
            eyebrow: "Pair the band",
            title: "Learn each cue\nbefore the room does.",
            body: "Connect your Cue Band and preview the vibration language. You can still rehearse with analytics only.",
            symbol: "applewatch.radiowaves.left.and.right"
        ),
        OnboardingPage(
            eyebrow: "Ready",
            title: "Put the phone down.\nStay in the moment.",
            body: "Keep the microphone unobstructed and the live screen open during your presentation.",
            symbol: "sparkles"
        )
    ]

    var body: some View {
        ZStack {
            CueTheme.canvas.ignoresSafeArea()
            Circle()
                .fill(CueTheme.violetSoft.opacity(0.70))
                .frame(width: 420, height: 420)
                .blur(radius: 30)
                .offset(x: 170, y: -330)
            VStack(spacing: 0) {
                HStack {
                    CueWordmark(compact: false)
                    Spacer()
                    Text("\(page + 1) / \(pages.count)")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? CueTheme.violet : CueTheme.border)
                            .frame(width: index == page ? 24 : 7, height: 7)
                            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: page)
                    }
                }
                .padding(.bottom, 20)

                VoxaButton(
                    title: page == pages.count - 1 ? "Start coaching" : nextButtonTitle,
                    symbol: page == pages.count - 1 ? "arrow.right" : "chevron.right",
                    style: .primary,
                    disabled: false,
                    action: advance
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
    }

    private var nextButtonTitle: String {
        page == 2 ? "Pair Cue Band" : "Continue"
    }

    private func advance() {
        if page == 2 { model.connectCueBand() }
        if page < pages.count - 1 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { page += 1 }
        } else {
            hasCompletedOnboarding = true
        }
    }
}

private struct OnboardingPage: Hashable {
    let eyebrow: String
    let title: String
    let body: String
    let symbol: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(CueTheme.surface)
                    .frame(height: 250)
                    .shadow(color: CueTheme.navy.opacity(0.08), radius: 30, y: 18)
                Circle()
                    .stroke(CueTheme.violet.opacity(0.22), lineWidth: 22)
                    .frame(width: 150, height: 150)
                Image(systemName: page.symbol)
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(CueTheme.violet)
                    .symbolEffect(.breathe, options: .repeating)
            }
            Text(page.eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(CueTheme.violet)
            Text(page.title)
                .font(.cueHero)
                .foregroundStyle(CueTheme.ink)
                .lineSpacing(-2)
            Text(page.body)
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .lineSpacing(4)
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
