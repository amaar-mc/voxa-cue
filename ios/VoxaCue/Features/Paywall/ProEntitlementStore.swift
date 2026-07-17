import Foundation
import Observation
import StoreKit

enum ProAccessSource: Equatable, Sendable {
    case locked
    case demo
    case storeKitTest
}

struct ProOffering: Equatable, Sendable {
    let displayName: String
    let displayPrice: String
}

enum ProPurchasePhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case purchasing
    case pending
    case cancelled
    case failed
}

@MainActor
@Observable
final class ProEntitlementStore {
    static let monthlyProductID = "com.amaarmc.voxacue.pro.monthly"

    private static let demoAccessKey = "voxaCue.demoProAccess.enabled"

    private(set) var accessSource: ProAccessSource
    private(set) var offering: ProOffering?
    private(set) var purchasePhase: ProPurchasePhase
    private(set) var notice: String?

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let productID: String
    @ObservationIgnored private let allowsDemoAccess: Bool
    @ObservationIgnored private var product: Product?
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    init(preferences: UserDefaults, productID: String, allowsDemoAccess: Bool) {
        self.preferences = preferences
        self.productID = productID
        self.allowsDemoAccess = allowsDemoAccess
        if !allowsDemoAccess {
            preferences.removeObject(forKey: Self.demoAccessKey)
        }
        self.accessSource = allowsDemoAccess && preferences.bool(forKey: Self.demoAccessKey)
            ? .demo
            : .locked
        self.offering = nil
        self.purchasePhase = .idle
        self.notice = nil
        self.product = nil
        self.transactionUpdatesTask = nil
    }

    var hasProAccess: Bool {
        accessSource != .locked
    }

    var demoAccessIsEnabled: Bool {
        allowsDemoAccess && preferences.bool(forKey: Self.demoAccessKey)
    }

    var accessLabel: String {
        switch accessSource {
        case .locked: "Preview locked"
        case .demo: "Demo Pro"
        case .storeKitTest: "StoreKit test access"
        }
    }

    func start() {
#if DEBUG
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            await self?.refresh()
            for await update in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.handleTransactionUpdate(update)
            }
        }
#else
        preferences.removeObject(forKey: Self.demoAccessKey)
        accessSource = .locked
#endif
    }

    func stop() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
    }

    func refresh() async {
        purchasePhase = .loading
        notice = nil

#if DEBUG
        await refreshAccessSource()
        do {
            product = try await Product.products(for: [productID]).first
            if let product {
                offering = ProOffering(
                    displayName: product.displayName,
                    displayPrice: product.displayPrice
                )
                purchasePhase = .ready
            } else {
                offering = nil
                purchasePhase = .failed
                notice = "Run the VoxaCue Xcode scheme to load the local StoreKit preview."
            }
        } catch {
            product = nil
            offering = nil
            purchasePhase = .failed
            notice = "The local StoreKit preview could not load."
        }
#else
        offering = nil
        product = nil
        purchasePhase = .failed
        notice = "Prototype purchases are available only in debug builds."
#endif
    }

    func purchaseLocalStoreKitPreview() async {
#if DEBUG
        guard let product else {
            purchasePhase = .failed
            notice = "The local StoreKit product is not loaded."
            return
        }

        purchasePhase = .purchasing
        notice = nil
        do {
            switch try await product.purchase() {
            case let .success(verification):
                switch verification {
                case let .verified(transaction):
                    await transaction.finish()
                    accessSource = .storeKitTest
                    purchasePhase = .ready
                    notice = "Local StoreKit test completed. No charge was made."
                case .unverified:
                    purchasePhase = .failed
                    notice = "StoreKit returned an unverified test transaction."
                }
            case .pending:
                purchasePhase = .pending
                notice = "The local StoreKit test is pending."
            case .userCancelled:
                purchasePhase = .cancelled
                notice = "Local purchase test cancelled."
            @unknown default:
                purchasePhase = .failed
                notice = "StoreKit returned an unknown test result."
            }
        } catch {
            purchasePhase = .failed
            notice = "The local StoreKit purchase test failed."
        }
#else
        purchasePhase = .failed
        notice = "Prototype purchases are available only in debug builds."
#endif
    }

    func setDemoAccess(enabled: Bool) {
        guard allowsDemoAccess else {
            preferences.removeObject(forKey: Self.demoAccessKey)
            accessSource = .locked
            notice = "Demo Pro is unavailable in this build."
            return
        }
        preferences.set(enabled, forKey: Self.demoAccessKey)
        guard accessSource != .storeKitTest else { return }
        accessSource = enabled ? .demo : .locked
        notice = enabled
            ? "Demo Pro is enabled on this iPhone. This is not a purchase."
            : "Demo Pro is off."
    }

#if DEBUG
    func recordVerifiedStoreKitAccessForTesting() {
        accessSource = .storeKitTest
    }
#endif

    private func refreshAccessSource() async {
        if await hasCurrentStoreKitEntitlement() {
            accessSource = .storeKitTest
        } else {
            accessSource = demoAccessIsEnabled ? .demo : .locked
        }
    }

    private func hasCurrentStoreKitEntitlement() async -> Bool {
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            guard transaction.productID == productID else { continue }
            guard transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            return true
        }
        return false
    }

    private func handleTransactionUpdate(
        _ result: VerificationResult<StoreKit.Transaction>
    ) async {
        guard case let .verified(transaction) = result else { return }
        guard transaction.productID == productID else { return }
        await transaction.finish()
        await refreshAccessSource()
    }
}
