import Foundation
import Testing
@testable import VoxaCue

@MainActor
@Test("Demo Pro access is explicitly labeled and persists across launches")
func demoProAccessPersists() throws {
    let suiteName = "VoxaCueTests.demo-pro-persistence"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)

    let store = ProEntitlementStore(
        preferences: preferences,
        productID: ProEntitlementStore.monthlyProductID,
        allowsDemoAccess: true
    )
    #expect(store.accessSource == .locked)
    #expect(store.hasProAccess == false)

    store.setDemoAccess(enabled: true)
    #expect(store.accessSource == .demo)
    #expect(store.hasProAccess)
    #expect(store.accessLabel == "Demo Pro")

    let relaunchedStore = ProEntitlementStore(
        preferences: preferences,
        productID: ProEntitlementStore.monthlyProductID,
        allowsDemoAccess: true
    )
    #expect(relaunchedStore.accessSource == .demo)
    #expect(relaunchedStore.hasProAccess)

    relaunchedStore.setDemoAccess(enabled: false)
    #expect(relaunchedStore.accessSource == .locked)
    #expect(relaunchedStore.hasProAccess == false)

    preferences.removePersistentDomain(forName: suiteName)
}

@MainActor
@Test("Turning off the demo switch cannot erase verified StoreKit access")
func demoSwitchDoesNotOverrideStoreKitAccess() throws {
    let suiteName = "VoxaCueTests.demo-pro-storekit-precedence"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)
    let store = ProEntitlementStore(
        preferences: preferences,
        productID: ProEntitlementStore.monthlyProductID,
        allowsDemoAccess: true
    )

    store.recordVerifiedStoreKitAccessForTesting()
    store.setDemoAccess(enabled: false)

    #expect(store.accessSource == .storeKitTest)
    #expect(store.hasProAccess)
    #expect(store.accessLabel == "StoreKit test access")

    preferences.removePersistentDomain(forName: suiteName)
}

@MainActor
@Test("Release-style entitlement store ignores persisted demo access")
func releaseStyleStoreRejectsDemoAccess() throws {
    let suiteName = "VoxaCueTests.demo-pro-release-lock"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)
    preferences.set(true, forKey: "voxaCue.demoProAccess.enabled")

    let store = ProEntitlementStore(
        preferences: preferences,
        productID: ProEntitlementStore.monthlyProductID,
        allowsDemoAccess: false
    )
    store.setDemoAccess(enabled: true)

    #expect(store.accessSource == .locked)
    #expect(store.hasProAccess == false)
    #expect(store.demoAccessIsEnabled == false)
    #expect(preferences.bool(forKey: "voxaCue.demoProAccess.enabled") == false)

    preferences.removePersistentDomain(forName: suiteName)
}
