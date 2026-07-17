import SwiftUI

struct ProInsightsGateCard: View {
    let action: () -> Void

    var body: some View {
        HeroCard(padding: CueTheme.Space.xLarge) {
            VStack(alignment: .leading, spacing: CueTheme.Space.medium) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CueTheme.signal)
                        .frame(width: 46, height: 46)
                        .background(CueTheme.signalSoft)
                        .clipShape(Circle())
                    Spacer(minLength: CueTheme.Space.small)
                    Label("Pro preview", systemImage: "lock")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.haptic)
                }

                Text("Your delivery changes session by session.")
                    .font(.cueSection)
                    .foregroundStyle(CueTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Unlock long-term pace, filler, pause, timing, and intonation trends.")
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                VoxaButton(
                    title: "Preview Voxa Cue Pro",
                    symbol: "arrow.right",
                    style: .secondary,
                    disabled: false,
                    action: action
                )
            }
        }
    }
}
