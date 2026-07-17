import AVFoundation
import Foundation
import Testing
import VoxaCore
import VoxaRuntime
@testable import VoxaCue

private struct LegacyHapticPreferences: Encodable {
    let enabledCues: Set<CueKind>
    let patternByCue: [CueKind: HapticPattern]
    let intensityByCue: [CueKind: CueIntensity]
}

@Test("Local deck planning preserves order and lands exactly on target time")
func localDeckPlanTiming() {
    let slides = [
        DeckSlide(
            id: UUID(),
            index: 1,
            title: "Problem",
            body: "Presenters lose useful feedback when pressure changes their delivery.",
            notes: "Explain the current workflow."
        ),
        DeckSlide(
            id: UUID(),
            index: 2,
            title: "Voxa Cue",
            body: "Private live haptics help speakers adjust pace, fillers, and timing.",
            notes: "Close with the coaching loop."
        )
    ]

    let plan = LocalDeckPlanner.makePlan(
        title: "Pitch",
        targetDurationSeconds: 180,
        slides: slides
    )

    #expect(plan.checkpoints.map(\.slideIndex) == [1, 2])
    #expect(plan.checkpoints[0].targetCumulativeSeconds < 180)
    #expect(plan.checkpoints[1].targetCumulativeSeconds == 180)
    #expect(plan.checkpoints.allSatisfy { $0.anchorTerms.count >= 2 })
}

@Test("Sparse slides receive conservative fallback anchors")
func localDeckPlanFallbackAnchors() {
    let slides = [
        DeckSlide(
            id: UUID(),
            index: 1,
            title: "Go",
            body: "Now",
            notes: "End"
        )
    ]

    let plan = LocalDeckPlanner.makePlan(
        title: "Brief",
        targetDurationSeconds: 30,
        slides: slides
    )

    #expect(plan.checkpoints[0].anchorTerms == ["slide", "topic"])
}

@Test("Retiming a prepared deck is local and preserves coaching anchors")
func preparedDeckRetimingPreservesContent() {
    let original = DeckPlan(
        schemaVersion: 1,
        title: "Investor pitch",
        checkpoints: [
            DeckCheckpoint(
                id: "slide-1",
                slideIndex: 1,
                label: "Problem",
                targetCumulativeSeconds: 60,
                semanticSummary: "Presenters lose feedback under pressure.",
                anchorTerms: ["presenters", "pressure"]
            ),
            DeckCheckpoint(
                id: "slide-2",
                slideIndex: 2,
                label: "Product",
                targetCumulativeSeconds: 180,
                semanticSummary: "Voxa Cue closes the coaching loop.",
                anchorTerms: ["coaching", "haptics"]
            )
        ]
    )

    let retimed = LocalDeckPlanner.retime(plan: original, targetDurationSeconds: 120)

    #expect(retimed.title == original.title)
    #expect(retimed.schemaVersion == original.schemaVersion)
    #expect(retimed.checkpoints.map(\.targetCumulativeSeconds) == [40, 120])
    #expect(retimed.checkpoints.map(\.semanticSummary) == original.checkpoints.map(\.semanticSummary))
    #expect(retimed.checkpoints.map(\.anchorTerms) == original.checkpoints.map(\.anchorTerms))
}

@MainActor
@Test("App model hydrates saved insights with session history")
func appModelHydratesSavedInsights() throws {
    let dataStore = try VoxaDataStore(inMemory: true)
    let summary = try #require(DemoFixtures.sessions().first)
    let insight = DemoFixtures.insight()
    try dataStore.saveSession(
        summary: summary,
        segments: [],
        samples: [],
        cueEvents: [],
        checkpointResults: []
    )
    try dataStore.saveInsight(sessionID: summary.sessionID, insight: insight)
    let preferences = try #require(UserDefaults(suiteName: "VoxaCueTests.saved-insight-hydration"))
    preferences.removePersistentDomain(forName: "VoxaCueTests.saved-insight-hydration")

    let model = AppModel(
        dataStore: dataStore,
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )

    #expect(model.sessions == [summary])
    #expect(model.insightBySession[summary.sessionID] == insight)
}

@MainActor
@Test("App model repairs missing legacy haptic mappings without replacing custom choices")
func appModelNormalizesLegacyHapticPreferences() throws {
    let suiteName = "VoxaCueTests.legacy-haptic-preferences"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)
    let legacy = LegacyHapticPreferences(
        enabledCues: Set(CueKind.essentialDefaults),
        patternByCue: [.tooFast: .singlePulse],
        intensityByCue: [.tooFast: .strong]
    )
    preferences.set(
        try JSONEncoder().encode(legacy),
        forKey: "voxaCueHapticPreferencesV1"
    )

    let model = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )

    #expect(model.hapticPreferences.enabledCues == legacy.enabledCues)
    #expect(model.hapticPreferences.patternByCue[.tooFast] == .singlePulse)
    #expect(model.hapticPreferences.intensityByCue[.tooFast] == .strong)
    #expect(model.hapticPreferences.patternByCue[.fillerBurst] == .calmWave)
    #expect(model.hapticPreferences.intensityByCue[.time100] == .strong)
    #expect(model.hapticPreferences.fillerClusterConfiguration == .responsiveDefault())
    let migratedData = try #require(preferences.data(forKey: "voxaCueHapticPreferencesV1"))
    let migrated = try JSONDecoder().decode(HapticPreferences.self, from: migratedData)
    #expect(migrated == model.hapticPreferences)
}

@MainActor
@Test("App model repairs invalid filler cluster settings without replacing custom choices")
func appModelNormalizesInvalidFillerClusterConfiguration() throws {
    let suiteName = "VoxaCueTests.invalid-filler-cluster-configuration"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)
    let customPreferences = HapticPreferences(
        enabledCues: Set(CueKind.essentialDefaults),
        patternByCue: [.tooFast: .singlePulse],
        intensityByCue: [.tooFast: .strong],
        fillerClusterConfiguration: FillerClusterConfiguration(requiredFillerCount: 4, windowSeconds: 15)
    )
    let encoded = try JSONEncoder().encode(customPreferences)
    var payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    payload["fillerClusterConfiguration"] = [
        "requiredFillerCount": 99,
        "windowSeconds": 3,
    ]
    preferences.set(
        try JSONSerialization.data(withJSONObject: payload),
        forKey: "voxaCueHapticPreferencesV1"
    )

    let model = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )

    #expect(model.hapticPreferences.enabledCues == customPreferences.enabledCues)
    #expect(model.hapticPreferences.patternByCue[.tooFast] == .singlePulse)
    #expect(model.hapticPreferences.intensityByCue[.tooFast] == .strong)
    #expect(model.hapticPreferences.fillerClusterConfiguration == .responsiveDefault())
}

@MainActor
@Test("Filler cluster settings persist with haptic preferences")
func appModelPersistsFillerClusterConfiguration() throws {
    let suiteName = "VoxaCueTests.filler-cluster-configuration"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)
    let model = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )

    let customConfiguration = FillerClusterConfiguration(requiredFillerCount: 4, windowSeconds: 15)
    model.setFillerClusterConfiguration(customConfiguration)

    let storedData = try #require(preferences.data(forKey: "voxaCueHapticPreferencesV1"))
    let stored = try JSONDecoder().decode(HapticPreferences.self, from: storedData)
    #expect(stored.fillerClusterConfiguration == customConfiguration)

    let reloadedModel = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )
    #expect(reloadedModel.hapticPreferences.fillerClusterConfiguration == customConfiguration)
}

@MainActor
@Test("Demo mode never contacts the coaching API")
func demoModeAvoidsCoachingAPI() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UnexpectedRequestURLProtocol.self]
    let apiClient = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "demo-mode-must-not-send",
        session: URLSession(configuration: configuration),
        requestTimeoutSeconds: 28
    )
    let preferences = try #require(UserDefaults(suiteName: "VoxaCueTests.demo-api-avoidance"))
    preferences.removePersistentDomain(forName: "VoxaCueTests.demo-api-avoidance")
    let model = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: apiClient,
        demoMode: true,
        preferences: preferences
    )
    let summary = try #require(model.sessions.first)
    let slides = [
        DeckSlide(
            id: UUID(),
            index: 1,
            title: "Solution",
            body: "Voxa Cue turns live delivery metrics into private haptic feedback.",
            notes: "Explain the coaching loop."
        )
    ]

    let preparedPlan = await model.createDeckPlan(title: "Demo pitch", targetDurationSeconds: 90, slides: slides)
    await model.generateInsight(for: summary)

    #expect(preparedPlan.source == .local)
    #expect(preparedPlan.plan.checkpoints.last?.targetCumulativeSeconds == 90)
    #expect(model.insightBySession[summary.sessionID] == DemoFixtures.insight())
}

@MainActor
@Test("App model reports coaching API readiness with its deployed build")
func appModelReportsCoachingAPIReadiness() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ReadyAPIURLProtocol.self]
    let apiClient = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "readiness-test-token-with-32-characters",
        session: URLSession(configuration: configuration),
        requestTimeoutSeconds: 28
    )
    let preferences = try #require(UserDefaults(suiteName: "VoxaCueTests.api-readiness"))
    preferences.removePersistentDomain(forName: "VoxaCueTests.api-readiness")
    let model = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: apiClient,
        demoMode: false,
        preferences: preferences
    )

    await model.checkCoachingAPI()

    #expect(model.coachingAPIState == .ready(build: "ios-test-build"))
}

@Test("Demo fixtures are stable across independent loads")
func demoFixturesAreDeterministic() {
    #expect(DemoFixtures.sessions() == DemoFixtures.sessions())
    #expect(DemoFixtures.insight() == DemoFixtures.insight())
}

@Test("Session summaries disclose deterministic demo evidence")
func sessionSummaryDisclosesDemoEvidence() {
    #expect(summaryEvidenceDisclosure(isDemoMode: true) == "Deterministic demo data")
    #expect(summaryEvidenceDisclosure(isDemoMode: false) == nil)
}

@Test("Live cue presentation never overstates wrist delivery")
func liveCueDeliveryPresentationIsTruthful() {
    #expect(cueDeliveryPresentation(status: .pending, demoMode: false) == .sending)
    #expect(cueDeliveryPresentation(status: .accepted, demoMode: false) == .accepted)
    #expect(cueDeliveryPresentation(status: .completed, demoMode: false) == .completed)
    #expect(cueDeliveryPresentation(status: .failed, demoMode: false) == .failed)
    #expect(cueDeliveryPresentation(status: .notConnected, demoMode: false) == .analyticsOnly)
    #expect(cueDeliveryPresentation(status: .suppressed, demoMode: false) == .analyticsOnly)
    #expect(cueDeliveryPresentation(status: .completed, demoMode: true) == .simulated)
}

@MainActor
@Test("Leaving the foreground pauses coaching until the presenter explicitly resumes")
func lifecyclePauseRequiresExplicitResume() throws {
    let controller = try makeSessionControllerForBehaviorTests(demoMode: true)
    controller.phase = .recording

    controller.pauseForLifecycle()
    controller.pauseForLifecycle()

    #expect(controller.phase == .paused(.appInactive))
    controller.togglePause()
    #expect(controller.phase == .recording)
}

@MainActor
@Test("Live session light follows progress, pause, overtime, and finish")
func liveSessionLightFollowsSessionLifecycle() async throws {
    var sentLights: [CueSessionLight] = []
    let controller = LiveSessionController(
        configuration: behaviorTestSessionConfiguration(),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        dataStore: try VoxaDataStore(inMemory: true),
        semanticMatcher: SemanticMatcher(),
        demoMode: true,
        allocateCueSequence: { 1 },
        sendCue: { _ in },
        sendSessionLight: { sentLights.append($0) },
        monotonicNow: { 100 },
        cueDeliveryDeadlines: CueDeliveryDeadlineConfiguration(
            acceptanceTimeoutSeconds: 2,
            completionTimeoutSeconds: 4
        ),
        onFinish: { _ in }
    )
    controller.phase = .recording
    controller.metrics = LiveMetrics(
        elapsedSeconds: 60,
        rollingWPM: 145,
        finalizedWordCount: 145,
        fillerCount: 0,
        voicedSeconds: 45,
        talkRatio: 0.75,
        energyDBFS: nil,
        pitchHertz: nil
    )

    controller.resendSessionLight()
    controller.togglePause()
    controller.togglePause()
    controller.metrics = LiveMetrics(
        elapsedSeconds: 120.1,
        rollingWPM: 145,
        finalizedWordCount: 290,
        fillerCount: 0,
        voicedSeconds: 90,
        talkRatio: 0.75,
        energyDBFS: nil,
        pitchHertz: nil
    )
    controller.resendSessionLight()
    await controller.finish()

    #expect(sentLights == [
        CueSessionLight(mode: .active, progressPercent: 50),
        CueSessionLight(mode: .paused, progressPercent: 50),
        CueSessionLight(mode: .active, progressPercent: 50),
        CueSessionLight(mode: .overtime, progressPercent: 100),
        CueSessionLight(mode: .off, progressPercent: 0),
    ])
}

@MainActor
@Test("Entering the background during preparation cancels session startup")
func backgroundingCancelsSessionStartup() async throws {
    let preferences = try #require(UserDefaults(suiteName: "VoxaCueTests.lifecycle-start-cancellation"))
    preferences.removePersistentDomain(forName: "VoxaCueTests.lifecycle-start-cancellation")
    let model = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: true,
        preferences: preferences
    )
    model.beginSession(configuration: behaviorTestSessionConfiguration())

    model.handleSceneEnteredBackground()
    await Task.yield()

    let controller = try #require(model.activeSession)
    guard case .failed = controller.phase else {
        Issue.record("Cancelled startup must remain failed, not restart in the background")
        return
    }
}

@MainActor
@Test("Permission-sheet inactivity does not cancel session startup")
func temporaryInactivityPreservesSessionStartup() async throws {
    let preferences = try #require(UserDefaults(suiteName: "VoxaCueTests.permission-inactivity"))
    preferences.removePersistentDomain(forName: "VoxaCueTests.permission-inactivity")
    let model = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: true,
        preferences: preferences
    )
    model.beginSession(configuration: behaviorTestSessionConfiguration())
    let controller = try #require(model.activeSession)

    model.handleSceneBecameInactive()
    await Task.yield()

    guard case .failed = controller.phase else {
        model.handleSceneEnteredBackground()
        return
    }
    Issue.record("Temporary inactivity must not cancel permission or countdown preparation")
}

@MainActor
@Test("Session setup dismisses before live presentation begins")
func sessionPresentationWaitsForSetupDismissal() async throws {
    let preferences = try #require(UserDefaults(suiteName: "VoxaCueTests.session-presentation-order"))
    preferences.removePersistentDomain(forName: "VoxaCueTests.session-presentation-order")
    let model = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: true,
        preferences: preferences
    )
    model.setupPresented = true

    model.beginSession(configuration: behaviorTestSessionConfiguration())

    #expect(model.setupPresented == false)
    #expect(model.activeSession == nil)

    model.presentPendingSession()
    #expect(model.activeSession != nil)
    model.handleSceneEnteredBackground()
    await Task.yield()
}

@MainActor
@Test("Lost band completion becomes terminal failed evidence")
func lostBandCompletionFailsTruthfully() throws {
    let controller = try makeSessionControllerForBehaviorTests(demoMode: true)
    controller.cueLogs = [
        LiveSessionController.CueLog(
            id: UUID(),
            sequence: 7,
            decision: CueDecision(kind: .tooFast, reason: "Speaking above target pace"),
            elapsedSeconds: 30,
            deliveryStatus: .pending,
            sentAtMonotonicSeconds: 99,
            acceptedAtMonotonicSeconds: nil
        )
    ]

    controller.handleBandStatus(
        CueBandStatus(
            sequence: 7,
            state: .accepted,
            error: .none,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )
    controller.expireCueDeliveryDeadlines(atMonotonicSeconds: 104)
    controller.handleBandStatus(
        CueBandStatus(
            sequence: 7,
            state: .completed,
            error: .none,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )

    #expect(controller.cueLogs[0].deliveryStatus == .failed)
    #expect(controller.latestBandFailure == "Cue Band did not confirm vibration completion in time.")
}

@MainActor
@Test("Band acceptance and completion confirm wrist delivery")
func bandAcknowledgementsConfirmDelivery() throws {
    let controller = try makeSessionControllerForBehaviorTests(demoMode: true)
    controller.cueLogs = [
        LiveSessionController.CueLog(
            id: UUID(),
            sequence: 9,
            decision: CueDecision(kind: .tooFast, reason: "Speaking above target pace"),
            elapsedSeconds: 30,
            deliveryStatus: .pending,
            sentAtMonotonicSeconds: 99,
            acceptedAtMonotonicSeconds: nil
        )
    ]

    controller.handleBandStatus(
        CueBandStatus(
            sequence: 9,
            state: .accepted,
            error: .none,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )
    #expect(controller.cueLogs[0].deliveryStatus == .accepted)

    controller.handleBandStatus(
        CueBandStatus(
            sequence: 9,
            state: .completed,
            error: .none,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )
    #expect(controller.cueLogs[0].deliveryStatus == .completed)
    #expect(controller.latestBandFailure == nil)
}

@MainActor
@Test("Measured voice activity unlocks a persisted live pace cue")
func voiceActivityUnlocksLivePaceCue() throws {
    let controller = try makeSessionControllerForBehaviorTests(demoMode: false)
    controller.phase = .recording
    controller.metrics = LiveMetrics(
        elapsedSeconds: 20,
        rollingWPM: 180,
        finalizedWordCount: 30,
        fillerCount: 0,
        voicedSeconds: 0,
        talkRatio: 0,
        energyDBFS: nil,
        pitchHertz: nil
    )
    controller.handleSpeechEvent(
        .finalizedTranscript(
            text: Array(repeating: "word", count: 30).joined(separator: " "),
            startSeconds: 0,
            endSeconds: 20
        )
    )

    controller.handleSpeechEvent(
        .voiceActivity(isSpeech: true, startSeconds: 0, endSeconds: 12)
    )
    controller.evaluateLiveCue()

    #expect(controller.metrics.voicedSeconds == 12)
    #expect(controller.cueLogs.isEmpty)

    controller.metrics = LiveMetrics(
        elapsedSeconds: 24,
        rollingWPM: 180,
        finalizedWordCount: 36,
        fillerCount: 0,
        voicedSeconds: controller.metrics.voicedSeconds,
        talkRatio: controller.metrics.talkRatio,
        energyDBFS: nil,
        pitchHertz: nil
    )
    controller.handleSpeechEvent(
        .finalizedTranscript(
            text: Array(repeating: "word", count: 6).joined(separator: " "),
            startSeconds: 20,
            endSeconds: 24
        )
    )
    controller.handleSpeechEvent(
        .voiceActivity(isSpeech: true, startSeconds: 12, endSeconds: 16)
    )
    controller.evaluateLiveCue()

    #expect(controller.metrics.voicedSeconds == 16)
    #expect(controller.cueLogs.last?.decision.kind == .tooFast)
}

@MainActor
@Test("Live delivery fails closed on premature or erroneous completion")
func liveDeliveryRejectsInvalidCompletion() throws {
    let prematureController = try makeSessionControllerForBehaviorTests(demoMode: true)
    prematureController.cueLogs = [
        LiveSessionController.CueLog(
            id: UUID(),
            sequence: 21,
            decision: CueDecision(kind: .tooFast, reason: "Speaking above target pace"),
            elapsedSeconds: 30,
            deliveryStatus: .pending,
            sentAtMonotonicSeconds: 99,
            acceptedAtMonotonicSeconds: nil
        )
    ]
    prematureController.handleBandStatus(
        CueBandStatus(
            sequence: 21,
            state: .completed,
            error: .none,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )

    #expect(prematureController.cueLogs[0].deliveryStatus == .failed)
    #expect(prematureController.latestBandFailure == "Cue completion arrived before acceptance.")

    let faultController = try makeSessionControllerForBehaviorTests(demoMode: true)
    faultController.cueLogs = [
        LiveSessionController.CueLog(
            id: UUID(),
            sequence: 22,
            decision: CueDecision(kind: .tooFast, reason: "Speaking above target pace"),
            elapsedSeconds: 30,
            deliveryStatus: .accepted,
            sentAtMonotonicSeconds: 99,
            acceptedAtMonotonicSeconds: 100
        )
    ]
    faultController.handleBandStatus(
        CueBandStatus(
            sequence: 22,
            state: .completed,
            error: .driverFault,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )

    #expect(faultController.cueLogs[0].deliveryStatus == .failed)
    #expect(faultController.latestBandFailure == "Haptic driver fault")
}

@Test("Device Lab requires matching acceptance before completion")
func deviceLabCorrelatesAcknowledgements() {
    let awaiting = DeviceLabCueDelivery.awaitingAcceptance(sequence: 42)
    let unrelated = reduceDeviceLabCueDelivery(
        awaiting,
        status: CueBandStatus(
            sequence: 41,
            state: .completed,
            error: .none,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )
    let accepted = reduceDeviceLabCueDelivery(
        awaiting,
        status: CueBandStatus(
            sequence: 42,
            state: .accepted,
            error: .none,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )
    let completed = reduceDeviceLabCueDelivery(
        accepted,
        status: CueBandStatus(
            sequence: 42,
            state: .completed,
            error: .none,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )
    let premature = reduceDeviceLabCueDelivery(
        awaiting,
        status: CueBandStatus(
            sequence: 42,
            state: .completed,
            error: .none,
            firmwareMajor: 1,
            firmwareMinor: 0
        )
    )

    #expect(unrelated == awaiting)
    #expect(accepted == .awaitingCompletion(sequence: 42))
    #expect(completed == .completed(sequence: 42))
    #expect(premature == .failed(sequence: 42, message: "Completion arrived before acceptance."))
}

@Test("Device Lab fails pending commands immediately when Bluetooth terminates")
func deviceLabHandlesTerminalConnectionStates() {
    let pending = DeviceLabCueDelivery.awaitingCompletion(sequence: 43)

    #expect(
        reduceDeviceLabCueDelivery(pending, connectionState: .failed("Write failed"))
            == .failed(sequence: 43, message: "Bluetooth failed: Write failed")
    )
    #expect(
        reduceDeviceLabCueDelivery(pending, connectionState: .bluetoothUnavailable)
            == .failed(
                sequence: 43,
                message: "Bluetooth became unavailable before the haptic was confirmed."
            )
    )
    #expect(reduceDeviceLabCueDelivery(pending, connectionState: .reconnecting) == pending)
}

@Test("Device Lab timeout copy identifies the missing acknowledgement phase")
func deviceLabTimeoutsArePhaseSpecific() {
    #expect(
        failDeviceLabCueDeliveryOnTimeout(.awaitingAcceptance(sequence: 44))
            == .failed(sequence: 44, message: "Timed out waiting for the command to be accepted.")
    )
    #expect(
        failDeviceLabCueDeliveryOnTimeout(.awaitingCompletion(sequence: 45))
            == .failed(
                sequence: 45,
                message: "The command was accepted, but vibration completion was not confirmed."
            )
    )
}

@Test("Local deck plans stay inside the persisted insight contract")
func localDeckPlanRespectsInsightBounds() {
    let slides = (0..<150).map { index in
        DeckSlide(
            id: UUID(),
            index: index,
            title: String(repeating: "Long title ", count: 20) + "\(index)",
            body: "Distinctive content for slide \(index) and the presentation narrative.",
            notes: "Explain evidence number \(index)."
        )
    }

    let plan = LocalDeckPlanner.makePlan(
        title: "Large pitch",
        targetDurationSeconds: 180,
        slides: slides
    )

    #expect(plan.checkpoints.count == 100)
    #expect(plan.checkpoints.allSatisfy { $0.label.count <= 120 })
    #expect(plan.checkpoints.allSatisfy { $0.semanticSummary.count <= 400 })
    #expect(zip(plan.checkpoints, plan.checkpoints.dropFirst()).allSatisfy {
        $0.targetCumulativeSeconds < $1.targetCumulativeSeconds
    })
    #expect(plan.checkpoints.last?.targetCumulativeSeconds == 180)
}

private final class UnexpectedRequestURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Issue.record("Demo mode attempted an unexpected API request")
        client?.urlProtocol(self, didFailWithError: URLError(.dataNotAllowed))
    }

    override func stopLoading() {}
}

@MainActor
private func makeSessionControllerForBehaviorTests(demoMode: Bool) throws -> LiveSessionController {
    LiveSessionController(
        configuration: behaviorTestSessionConfiguration(),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        dataStore: try VoxaDataStore(inMemory: true),
        semanticMatcher: SemanticMatcher(),
        demoMode: demoMode,
        allocateCueSequence: { 1 },
        sendCue: { _ in },
        sendSessionLight: { _ in },
        monotonicNow: { 100 },
        cueDeliveryDeadlines: CueDeliveryDeadlineConfiguration(
            acceptanceTimeoutSeconds: 2,
            completionTimeoutSeconds: 4
        ),
        onFinish: { _ in }
    )
}

private func behaviorTestSessionConfiguration() -> SessionConfiguration {
    SessionConfiguration(
        id: UUID(),
        name: "Lifecycle rehearsal",
        mode: .freeSpeaking,
        targetDurationSeconds: 120,
        profile: .rehearsalV1(),
        deckPlan: nil
    )
}

private final class ReadyAPIURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Data(
            #"{"status":"ready","service":"voxa-cue-api","schemaVersion":1,"build":"ios-test-build"}"#.utf8
        )
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
