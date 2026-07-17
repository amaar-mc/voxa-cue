import SwiftUI

struct DemoProSettingsCard: View {
    @Bindable var entitlementStore: ProEntitlementStore

    var body: some View {
        PremiumCard(padding: CueTheme.Space.large) {
            VStack(alignment: .leading, spacing: CueTheme.Space.medium) {
                HStack(spacing: 14) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CueTheme.signal)
                        .frame(width: 44, height: 44)
                        .background(CueTheme.signalSoft)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pro preview")
                            .font(.cueSection)
                            .foregroundStyle(CueTheme.ink)
                        Text(entitlementStore.accessLabel)
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                    Spacer(minLength: 8)
                }

                Toggle(
                    isOn: Binding(
                        get: { entitlementStore.demoAccessIsEnabled },
                        set: { entitlementStore.setDemoAccess(enabled: $0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Demo Pro on this iPhone")
                            .font(.cueBody.weight(.semibold))
                            .foregroundStyle(CueTheme.ink)
                        Text("A persisted showcase switch, not a purchase.")
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                }
                .tint(CueTheme.signal)
            }
        }
    }
}
