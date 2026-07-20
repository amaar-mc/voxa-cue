import SwiftUI

struct DemoProSettingsCard: View {
    @Bindable var entitlementStore: ProEntitlementStore

    var body: some View {
        PremiumCard(padding: CueTheme.Space.large) {
            Toggle(
                isOn: Binding(
                    get: { entitlementStore.demoAccessIsEnabled },
                    set: { entitlementStore.setDemoAccess(enabled: $0) }
                )
            ) {
                HStack(spacing: 14) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CueTheme.signal)
                        .frame(width: 44, height: 44)
                        .background(CueTheme.signalSoft)
                        .clipShape(Circle())
                    Text("Pro preview")
                        .font(.cueSection)
                        .foregroundStyle(CueTheme.ink)
                }
            }
            .tint(CueTheme.signal)
            .accessibilityHint("Enables the prototype Pro experience without a purchase")
        }
    }
}
