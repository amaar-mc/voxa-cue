import SwiftUI

struct VoxaProPaywallView: View {
    @Bindable var entitlementStore: ProEntitlementStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CueTheme.Space.large) {
                    hero
                    benefits
                    accessCard
                    disclosure
                }
                .padding(.horizontal, CueTheme.Space.large)
                .padding(.top, CueTheme.Space.medium)
                .padding(.bottom, CueTheme.Space.hero)
            }
            .background(CueTheme.canvas.ignoresSafeArea())
            .navigationTitle("Voxa Cue Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CueTheme.signal)
                }
            }
        }
        .task { entitlementStore.start() }
    }

    private var hero: some View {
        HeroCard(padding: CueTheme.Space.xLarge) {
            VStack(alignment: .leading, spacing: CueTheme.Space.medium) {
                HStack {
                    Label("Prototype preview", systemImage: "testtube.2")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.haptic)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(CueTheme.haptic.opacity(0.10))
                        .clipShape(Capsule())
                    Spacer(minLength: CueTheme.Space.small)
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(CueTheme.signal)
                        .frame(width: 48, height: 48)
                        .background(CueTheme.signalSoft)
                        .clipShape(Circle())
                }

                Text("See the pattern behind every presentation.")
                    .font(.cueTitle)
                    .foregroundStyle(CueTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Pro turns your saved sessions into clear delivery trends and private, consent-based coaching.")
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var benefits: some View {
        PremiumCard(padding: CueTheme.Space.large) {
            VStack(spacing: 0) {
                benefit(
                    symbol: "chart.line.uptrend.xyaxis",
                    title: "Long-term delivery trends",
                    detail: "Track pace, fillers, pauses, timing, and intonation across sessions."
                )
                Divider().padding(.leading, 50).overlay(CueTheme.border)
                benefit(
                    symbol: "scope",
                    title: "Focused next steps",
                    detail: "See the one or two habits with the strongest evidence to improve."
                )
                Divider().padding(.leading, 50).overlay(CueTheme.border)
                benefit(
                    symbol: "sparkles",
                    title: "Optional AI review",
                    detail: "Send the final transcript, aggregate metrics, and cue history only after you agree."
                )
            }
        }
    }

    private var accessCard: some View {
        PremiumCard(padding: CueTheme.Space.large) {
            VStack(alignment: .leading, spacing: CueTheme.Space.medium) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entitlementStore.accessLabel)
                            .font(.cueSection)
                            .foregroundStyle(CueTheme.ink)
                        Text(planLabel)
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                    Spacer(minLength: CueTheme.Space.small)
                    accessIndicator
                }

                if entitlementStore.hasProAccess {
                    VoxaButton(
                        title: "Continue to Pro preview",
                        symbol: "arrow.right",
                        style: .primary,
                        disabled: false,
                        action: { dismiss() }
                    )
                } else {
#if DEBUG
                    VoxaButton(
                        title: purchaseButtonTitle,
                        symbol: "apple.logo",
                        style: .primary,
                        disabled: purchaseButtonIsDisabled,
                        action: {
                            Task { await entitlementStore.purchaseLocalStoreKitPreview() }
                        }
                    )

                    Button {
                        entitlementStore.setDemoAccess(enabled: true)
                    } label: {
                        Text("Unlock Demo Pro on this iPhone")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(CueTheme.signal)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(SpringPressStyle())
#else
                    Text("Pro preview access is available only in internal builds.")
                        .font(.cueBody)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
#endif
                }

                if let notice = entitlementStore.notice {
                    Text(notice)
                        .font(.cueCaption)
                        .foregroundStyle(noticeColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
    }

    private var disclosure: some View {
        Label {
#if DEBUG
            Text("Xcode StoreKit test only. Demo Pro is an on-device preview switch. Neither path makes a real charge.")
                .fixedSize(horizontal: false, vertical: true)
#else
            Text("This build contains no active purchase or demo-unlock path.")
                .fixedSize(horizontal: false, vertical: true)
#endif
        } icon: {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(CueTheme.green)
        }
        .font(.cueCaption)
        .foregroundStyle(CueTheme.secondaryInk)
        .padding(.horizontal, CueTheme.Space.small)
    }

    private func benefit(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CueTheme.signal)
                .frame(width: 36, height: 36)
                .background(CueTheme.signalSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.cueBody.weight(.semibold))
                    .foregroundStyle(CueTheme.ink)
                Text(detail)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private var accessIndicator: some View {
        Image(systemName: entitlementStore.hasProAccess ? "checkmark" : "lock")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(entitlementStore.hasProAccess ? CueTheme.green : CueTheme.secondaryInk)
            .frame(width: 32, height: 32)
            .background(
                entitlementStore.hasProAccess
                    ? CueTheme.green.opacity(0.10)
                    : CueTheme.canvas
            )
            .clipShape(Circle())
    }

    private var planLabel: String {
        if let offering = entitlementStore.offering {
            return "\(offering.displayName) · \(offering.displayPrice) local test"
        }
        return "Local StoreKit preview"
    }

    private var purchaseButtonTitle: String {
        switch entitlementStore.purchasePhase {
        case .loading: "Loading local StoreKit…"
        case .purchasing: "Running purchase test…"
        case .pending: "Purchase test pending"
        case .idle, .ready, .cancelled, .failed: "Run local purchase test"
        }
    }

    private var purchaseButtonIsDisabled: Bool {
        entitlementStore.offering == nil
            || entitlementStore.purchasePhase == .loading
            || entitlementStore.purchasePhase == .purchasing
            || entitlementStore.purchasePhase == .pending
    }

    private var noticeColor: Color {
        entitlementStore.purchasePhase == .failed ? CueTheme.red : CueTheme.secondaryInk
    }
}
