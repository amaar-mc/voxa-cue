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

private func appRoadmapFixture() -> PracticeRoadmap {
    PracticeRoadmap(
        schemaVersion: 1,
        headline: "Pause before the first claim",
        summary: "Replace filler starts with silence while preserving your steady pace.",
        focusFillers: [
            RoadmapFillerFocus(phrase: "um", count: 1, guidance: "Use one quiet beat instead.")
        ],
        steps: [
            RoadmapStep(phase: .now, title: "Reset", evidence: "One um appeared.", action: "Pause.", measurableTarget: "Zero ums."),
            RoadmapStep(phase: .next, title: "Pace", evidence: "Pace was stable.", action: "Hold it.", measurableTarget: "80% in range."),
            RoadmapStep(phase: .then, title: "Voice", evidence: "Pitch was measured.", action: "Stress key words.", measurableTarget: "Practice three claims."),
        ],
        nextSessionGoal: RoadmapGoal(title: "Cleaner opening", measurement: "Likely filler count", target: "At most one"),
        confidenceNote: "Based on one finalized transcript and measured history."
    )
}

private func appNetworkRoadmapFixture(headline: String) -> PracticeRoadmap {
    PracticeRoadmap(
        schemaVersion: 1,
        headline: headline,
        summary: "Replace filler starts with silence while preserving a steady pace.",
        focusFillers: [
            RoadmapFillerFocus(phrase: "um", count: 2, guidance: "Use one quiet beat instead.")
        ],
        steps: [
            RoadmapStep(phase: .now, title: "Reset", evidence: "Two ums appeared.", action: "Pause.", measurableTarget: "One or fewer ums."),
            RoadmapStep(phase: .next, title: "Pace", evidence: "Pace was measured.", action: "Hold it.", measurableTarget: "80% in range."),
            RoadmapStep(phase: .then, title: "Voice", evidence: "Pitch was measured.", action: "Stress key words.", measurableTarget: "Practice three claims."),
        ],
        nextSessionGoal: RoadmapGoal(title: "Cleaner opening", measurement: "Likely filler count", target: "At most one"),
        confidenceNote: "Based on one finalized transcript and measured history."
    )
}

private func appAITestSummary(
    sessionID: UUID,
    name: String,
    startedAt: Date
) -> SessionSummary {
    SessionSummary(
        sessionID: sessionID,
        name: name,
        startedAt: startedAt,
        durationSeconds: 180,
        targetDurationSeconds: 180,
        targetMinimumWPM: 130,
        targetMaximumWPM: 160,
        speakingSeconds: 144,
        averageWPM: 148,
        timeInPaceRange: 0.78,
        fillerCount: 2,
        fillersPerSpeakingMinute: 0.83,
        talkRatio: 0.8,
        paceStandardDeviationWPM: 10,
        pauseCount: 5,
        averagePauseSeconds: 0.9,
        longestPauseSeconds: 1.6,
        pitchRangeSemitones: 7,
        energyRangeDB: 12,
        cueCount: 1,
        transcript: "Um, our product keeps feedback private. Um, the next step is deliberate practice."
    )
}

@Test("Local deck planning preserves order and lands exactly on target time")
func localDeckPlanTiming() throws {
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

    let plan = try LocalDeckPlanner.makePlan(
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
func localDeckPlanFallbackAnchors() throws {
    let slides = [
        DeckSlide(
            id: UUID(),
            index: 1,
            title: "Go",
            body: "Now",
            notes: "End"
        )
    ]

    let plan = try LocalDeckPlanner.makePlan(
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
@Test("App model hydrates the saved practice roadmap and clears it with its source session")
func appModelHydratesAndDeletesSavedRoadmap() throws {
    let dataStore = try VoxaDataStore(inMemory: true)
    let summary = try #require(DemoFixtures.sessions().first)
    let snapshot = SavedPracticeRoadmap(
        sourceSessionID: summary.sessionID,
        generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        roadmap: appRoadmapFixture()
    )
    try dataStore.saveSession(
        summary: summary,
        segments: [],
        samples: [],
        cueEvents: [],
        checkpointResults: []
    )
    try dataStore.saveRoadmap(snapshot)
    let suiteName = "VoxaCueTests.saved-roadmap-hydration"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)

    let model = AppModel(
        dataStore: dataStore,
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )

    #expect(model.practiceRoadmap == snapshot)

    model.deleteSession(summary)

    #expect(model.practiceRoadmap == nil)
    #expect(model.coachMessages.isEmpty)
}

@MainActor
@Test("Empty coach messages never start a request or enter conversation state")
func emptyCoachMessageIsIgnored() async throws {
    let suiteName = "VoxaCueTests.empty-coach-message"
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

    await model.sendCoachMessage("   ")

    #expect(model.coachMessages.isEmpty)
    #expect(model.isSendingCoachMessage == false)
}

@MainActor
@Test("The latest roadmap request wins when an older response arrives later")
func latestRoadmapGenerationWinsRace() async throws {
    DelayedRoadmapChatURLProtocol.state.reset()
    let summary = appAITestSummary(
        sessionID: UUID(uuidString: "C37A7194-B352-422B-910D-745039189FA5")!,
        name: "Roadmap race",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let (model, _) = try makeDelayedAIModel(
        summary: summary,
        savedRoadmap: nil,
        preferenceSuite: "VoxaCueTests.roadmap-generation-race"
    )

    let first = Task { await model.generateRoadmap(for: summary) }
    for _ in 0..<100 where DelayedRoadmapChatURLProtocol.state.count(path: "/v1/roadmaps") < 1 {
        try await Task.sleep(nanoseconds: 2_000_000)
    }
    let second = Task { await model.generateRoadmap(for: summary) }
    await second.value
    await first.value

    #expect(model.practiceRoadmap?.roadmap.headline == "Second roadmap")
    #expect(model.isGeneratingRoadmap == false)
}

@MainActor
@Test("Closing coach chat discards a late response and bounds local turns")
func clearingCoachConversationInvalidatesInFlightReply() async throws {
    DelayedRoadmapChatURLProtocol.state.reset()
    let summary = appAITestSummary(
        sessionID: UUID(uuidString: "25A31C7E-E7A7-4692-BBDE-E123A42E12AB")!,
        name: "Coach race",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let (model, _) = try makeDelayedAIModel(
        summary: summary,
        savedRoadmap: appNetworkRoadmapFixture(headline: "Coach source"),
        preferenceSuite: "VoxaCueTests.coach-clear-race"
    )

    let send = Task { await model.sendCoachMessage("How should I practice?") }
    for _ in 0..<100 where DelayedRoadmapChatURLProtocol.state.count(path: "/v1/coach-chat") < 1 {
        try await Task.sleep(nanoseconds: 2_000_000)
    }
    #expect(DelayedRoadmapChatURLProtocol.state.count(path: "/v1/coach-chat") == 1)

    model.clearCoachConversation()
    await send.value

    #expect(model.coachMessages.isEmpty)
    #expect(model.isSendingCoachMessage == false)
}

@MainActor
@Test("Deleting a session discards an in-flight roadmap response")
func deletingSessionInvalidatesInFlightRoadmap() async throws {
    DelayedRoadmapChatURLProtocol.state.reset()
    let summary = appAITestSummary(
        sessionID: UUID(uuidString: "7B639B49-2AB8-40C2-B250-7D20BB9DAEA9")!,
        name: "Roadmap deletion",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let (model, dataStore) = try makeDelayedAIModel(
        summary: summary,
        savedRoadmap: nil,
        preferenceSuite: "VoxaCueTests.roadmap-deletion-race"
    )

    let generation = Task { await model.generateRoadmap(for: summary) }
    for _ in 0..<100 where DelayedRoadmapChatURLProtocol.state.count(path: "/v1/roadmaps") < 1 {
        try await Task.sleep(nanoseconds: 2_000_000)
    }
    model.deleteSession(summary)
    await generation.value

    #expect(model.practiceRoadmap == nil)
    #expect(try dataStore.fetchLatestRoadmap() == nil)
    #expect(try dataStore.fetchSessions().isEmpty)
}

@MainActor
@Test("Deleting a session discards an in-flight coach reply")
func deletingSessionInvalidatesInFlightCoachReply() async throws {
    DelayedRoadmapChatURLProtocol.state.reset()
    let summary = appAITestSummary(
        sessionID: UUID(uuidString: "39E9435E-6771-45AA-B8BF-E40FCA1F5067")!,
        name: "Coach deletion",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let (model, _) = try makeDelayedAIModel(
        summary: summary,
        savedRoadmap: appNetworkRoadmapFixture(headline: "Coach deletion source"),
        preferenceSuite: "VoxaCueTests.coach-deletion-race"
    )

    let send = Task { await model.sendCoachMessage("How should I practice?") }
    for _ in 0..<100 where DelayedRoadmapChatURLProtocol.state.count(path: "/v1/coach-chat") < 1 {
        try await Task.sleep(nanoseconds: 2_000_000)
    }
    model.deleteSession(summary)
    await send.value

    #expect(model.practiceRoadmap == nil)
    #expect(model.coachMessages.isEmpty)
}

@MainActor
@Test("Deleting any aggregate contributor clears the visible roadmap")
func deletingRoadmapContributorClearsAppState() throws {
    let dataStore = try VoxaDataStore(inMemory: true)
    let source = try #require(DemoFixtures.sessions().first)
    let contributor = try #require(DemoFixtures.sessions().last)
    for summary in [source, contributor] {
        try dataStore.saveSession(
            summary: summary,
            segments: [],
            samples: [],
            cueEvents: [],
            checkpointResults: []
        )
    }
    try dataStore.saveRoadmap(
        SavedPracticeRoadmap(
            sourceSessionID: source.sessionID,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            roadmap: appRoadmapFixture()
        )
    )
    let suiteName = "VoxaCueTests.roadmap-contributor-deletion"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)
    let model = AppModel(
        dataStore: dataStore,
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )

    model.deleteSession(contributor)

    #expect(model.practiceRoadmap == nil)
    #expect(model.coachMessages.isEmpty)
}

@MainActor
@Test("Deleting a practice session updates visible history and selected details")
func appModelDeletesOnePracticeSession() throws {
    let dataStore = try VoxaDataStore(inMemory: true)
    let summaries = Array(DemoFixtures.sessions().prefix(2))
    let target = try #require(summaries.first)
    let retained = try #require(summaries.last)
    let insight = DemoFixtures.insight()
    for summary in summaries {
        try dataStore.saveSession(
            summary: summary,
            segments: [],
            samples: [],
            cueEvents: [],
            checkpointResults: []
        )
        try dataStore.saveInsight(sessionID: summary.sessionID, insight: insight)
    }
    let suiteName = "VoxaCueTests.single-session-deletion"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)
    let model = AppModel(
        dataStore: dataStore,
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )
    model.selectedSummary = target

    model.deleteSession(target)

    #expect(model.sessions == [retained])
    #expect(model.selectedSummary == nil)
    #expect(model.insightBySession[target.sessionID] == nil)
    #expect(try dataStore.fetchSessions() == [retained])
}

@MainActor
@Test("Deleting a session prevents an in-flight insight from recreating private data")
func deletingSessionInvalidatesInFlightInsight() async throws {
    let dataStore = try VoxaDataStore(inMemory: true)
    let summary = try #require(DemoFixtures.sessions().first)
    try dataStore.saveSession(
        summary: summary,
        segments: [],
        samples: [],
        cueEvents: [],
        checkpointResults: []
    )
    DelayedInsightURLProtocol.requestGate.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DelayedInsightURLProtocol.self]
    let apiClient = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "privacy-race-test-token-with-32-characters",
        session: URLSession(configuration: configuration),
        requestTimeoutSeconds: 28
    )
    let suiteName = "VoxaCueTests.insight-deletion-race"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)
    let model = AppModel(
        dataStore: dataStore,
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: apiClient,
        demoMode: false,
        preferences: preferences
    )

    let generation = Task { await model.generateInsight(for: summary) }
    for _ in 0..<100 where !DelayedInsightURLProtocol.requestGate.didStart {
        try await Task.sleep(nanoseconds: 2_000_000)
    }
    #expect(DelayedInsightURLProtocol.requestGate.didStart)

    model.deleteSession(summary)
    await generation.value

    #expect(model.insightBySession[summary.sessionID] == nil)
    #expect(try dataStore.fetchInsight(sessionID: summary.sessionID) == nil)
    #expect(try dataStore.fetchSessions().isEmpty)
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
@Test("Fresh installs present onboarding and persist skipping")
func freshInstallOnboardingPersistsSkipping() throws {
    let suiteName = "VoxaCueTests.onboarding-first-run"
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

    #expect(model.onboardingPresentation == .firstRun)
    #expect(model.hapticPreferences == .defaultsV1())

    model.skipOnboarding()

    #expect(model.onboardingPresentation == nil)
    #expect(preferences.bool(forKey: "hasCompletedVoxaOnboarding"))

    let reloadedModel = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )
    #expect(reloadedModel.onboardingPresentation == nil)
}

@MainActor
@Test("Replaying or skipping onboarding preserves customized cues")
func replayedOnboardingPreservesCustomizedCues() throws {
    let suiteName = "VoxaCueTests.onboarding-replay"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    preferences.removePersistentDomain(forName: suiteName)
    preferences.set(true, forKey: "hasCompletedVoxaOnboarding")
    let model = AppModel(
        dataStore: try VoxaDataStore(inMemory: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        cueBandClient: CueBandClient(),
        apiClient: nil,
        demoMode: false,
        preferences: preferences
    )
    model.setCuePattern(.tooFast, pattern: .singlePulse)
    let customizedHaptics = model.hapticPreferences

    model.presentOnboarding()
    #expect(model.onboardingPresentation == .replay)

    model.skipOnboarding()

    #expect(model.onboardingPresentation == nil)
    #expect(model.hapticPreferences == customizedHaptics)
    #expect(preferences.bool(forKey: "hasCompletedVoxaOnboarding"))
}

@MainActor
@Test("Onboarding can route directly into guided presentation setup")
func onboardingRoutesIntoSessionSetup() throws {
    let suiteName = "VoxaCueTests.onboarding-session-setup"
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
    model.selectedTab = .settings
    model.connectionState = .ready(firmware: "1.4")

    model.completeOnboarding(setupIntent: .presentation)

    #expect(model.onboardingPresentation == nil)
    #expect(model.selectedTab == .today)
    #expect(model.setupPresented)
    #expect(model.sessionSetupIntent == .presentation)
    #expect(preferences.bool(forKey: "hasCompletedVoxaOnboarding"))
}

@MainActor
@Test("Session setup stays closed until the Cue Band is connected")
func sessionSetupRequiresConnectedCueBand() throws {
    let suiteName = "VoxaCueTests.session-setup-connection-gate"
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
    model.selectedTab = .sessions

    model.presentSessionSetup(intent: .presentation)

    #expect(!model.setupPresented)
    #expect(model.selectedTab == .today)
    #expect(model.lastError == "Connect your Cue Band before setting up a session.")

    model.connectionState = .ready(firmware: "1.4")
    model.lastError = nil
    model.presentSessionSetup(intent: .presentation)

    #expect(model.setupPresented)
    #expect(model.sessionSetupIntent == .presentation)
    #expect(model.lastError == nil)
}

@Test("Pace presets provide clear and distinct coaching ranges")
func pacePresetRanges() {
    #expect(SpeakingPacePreset.slow.range == 100...130)
    #expect(SpeakingPacePreset.normal.range == 130...160)
    #expect(SpeakingPacePreset.fast.range == 160...190)
    #expect(SpeakingPacePreset.matching(minimumWPM: 130, maximumWPM: 160) == .normal)
    #expect(SpeakingPacePreset.matching(minimumWPM: 125, maximumWPM: 165) == nil)
}

@Test("Session setup describes haptics as explicit pulses")
func hapticPatternDescriptionsNamePulses() {
    #expect(hapticPatternPulseDescription(.doubleTap) == "2 short pulses")
    #expect(hapticPatternPulseDescription(.longShortLong) == "Long, short, long pulses")
    #expect(hapticPatternPulseDescription(.calmWave) == "1 gradual pulse")
}

@Test("Session setup keeps the emergency buzzer off unless explicitly enabled")
func sessionConfigurationKeepsEmergencyBuzzerOptIn() {
    let disabled = behaviorTestSessionConfiguration(emergencyBuzzerEnabled: false)
    let enabled = behaviorTestSessionConfiguration(emergencyBuzzerEnabled: true)

    #expect(!disabled.emergencyBuzzerEnabled)
    #expect(enabled.emergencyBuzzerEnabled)
}

@Test("A failed replacement keeps the current presentation explicit")
func presentationReplacementFailureCopyPreservesContext() {
    #expect(
        presentationImportFailureMessage(
            errorDescription: "The PDF is damaged.",
            retainsCurrentPresentation: true
        ) == "The PDF is damaged. Your current presentation is unchanged."
    )
    #expect(
        presentationImportFailureMessage(
            errorDescription: "The PDF is damaged.",
            retainsCurrentPresentation: false
        ) == "The PDF is damaged."
    )
}

@Test("Simple slide timing never presents an impossible average")
func simpleSlideTimingCopyRequiresEnoughTime() {
    #expect(
        simplePresentationTimingDescription(
            targetDurationSeconds: 60,
            slideCount: 100
        ) == "Increase target to at least 2 min"
    )
    #expect(
        simplePresentationTimingDescription(
            targetDurationSeconds: 300,
            slideCount: 7
        ) == "Divide evenly · about 0:43 per slide"
    )
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

    let preparedPlan = try await model.createDeckPlan(title: "Demo pitch", targetDurationSeconds: 90, slides: slides)
    await model.generateInsight(for: summary)
    await model.generateRoadmap(for: summary)
    for index in 1...6 {
        await model.sendCoachMessage("Demo coaching question \(index)")
    }

    #expect(preparedPlan.source == .local)
    #expect(preparedPlan.plan.checkpoints.last?.targetCumulativeSeconds == 90)
    #expect(model.insightBySession[summary.sessionID] == DemoFixtures.insight())
    #expect(model.practiceRoadmap?.roadmap == DemoFixtures.roadmap())
    #expect(model.coachMessages.count == 10)
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
        configuration: behaviorTestSessionConfiguration(emergencyBuzzerEnabled: false),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        dataStore: try VoxaDataStore(inMemory: true),
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
@Test("Live session requests the emergency buzzer at thirty seconds overtime")
func liveSessionRequestsEmergencyBuzzerAtThreshold() throws {
    var sentLights: [CueSessionLight] = []
    let controller = LiveSessionController(
        configuration: behaviorTestSessionConfiguration(emergencyBuzzerEnabled: true),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        dataStore: try VoxaDataStore(inMemory: true),
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
        elapsedSeconds: 150,
        rollingWPM: 145,
        finalizedWordCount: 360,
        fillerCount: 0,
        voicedSeconds: 120,
        talkRatio: 0.8,
        energyDBFS: nil,
        pitchHertz: nil
    )

    controller.resendSessionLight()

    #expect(sentLights == [CueSessionLight(mode: .overtimeEmergency, progressPercent: 100)])
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
    model.beginSession(configuration: behaviorTestSessionConfiguration(emergencyBuzzerEnabled: false))

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
    model.beginSession(configuration: behaviorTestSessionConfiguration(emergencyBuzzerEnabled: false))
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

    model.beginSession(configuration: behaviorTestSessionConfiguration(emergencyBuzzerEnabled: false))

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

@MainActor
@Test("A scheduled slide boundary sends one transition cue and advances the guide")
func scheduledSlideBoundarySendsOneCue() throws {
    var sentCommands: [CueCommand] = []
    let controller = try makeGuidedPresentationController(
        transitionCueEnabled: true,
        dataStore: VoxaDataStore(inMemory: true),
        sendCue: { sentCommands.append($0) }
    )
    controller.phase = .recording
    controller.metrics = guidedPresentationMetrics(elapsedSeconds: 30)

    controller.evaluateLiveCue()
    controller.evaluateLiveCue()

    #expect(sentCommands.map(\.pattern) == [.longShortLong])
    #expect(controller.cueLogs.map(\.decision.kind) == [.deckBehind])
    #expect(controller.currentPresentationSlideNumber == 2)
}

@MainActor
@Test("The on-screen slide guide advances when transition haptics are off")
func scheduledSlideBoundaryAdvancesWithoutHaptics() throws {
    var sentCommands: [CueCommand] = []
    let controller = try makeGuidedPresentationController(
        transitionCueEnabled: false,
        dataStore: VoxaDataStore(inMemory: true),
        sendCue: { sentCommands.append($0) }
    )
    controller.phase = .recording
    controller.metrics = guidedPresentationMetrics(elapsedSeconds: 30)

    controller.evaluateLiveCue()

    #expect(sentCommands.isEmpty)
    #expect(controller.cueLogs.isEmpty)
    #expect(controller.currentPresentationSlideNumber == 2)
}

@MainActor
@Test("A delayed timer catches up without bursting stale slide cues")
func delayedSlideTimerSendsAtMostOneCue() throws {
    var sentCommands: [CueCommand] = []
    let controller = try makeGuidedPresentationController(
        transitionCueEnabled: true,
        dataStore: VoxaDataStore(inMemory: true),
        sendCue: { sentCommands.append($0) }
    )
    controller.phase = .recording
    controller.metrics = guidedPresentationMetrics(elapsedSeconds: 60)

    controller.evaluateLiveCue()

    #expect(sentCommands.count == 1)
    #expect(controller.cueLogs.count == 1)
    #expect(controller.currentPresentationSlideNumber == 3)
}

@MainActor
@Test("Timed slide cues never fabricate observed slide-change analytics")
func timedSlideCuesDoNotPersistObservedCheckpoints() async throws {
    let dataStore = try VoxaDataStore(inMemory: true)
    let controller = try makeGuidedPresentationController(
        transitionCueEnabled: true,
        dataStore: dataStore,
        sendCue: { _ in }
    )
    controller.phase = .recording
    controller.metrics = guidedPresentationMetrics(elapsedSeconds: 60)
    controller.evaluateLiveCue()

    await controller.finish()

    let context = try dataStore.fetchInsightContext(sessionID: controller.id)
    #expect(context.checkpoints.isEmpty)
}

@Test("Local deck plans reject presentations above the supported slide limit")
func localDeckPlanRejectsOversizedPresentations() {
    let slides = (0..<150).map { index in
        DeckSlide(
            id: UUID(),
            index: index,
            title: String(repeating: "Long title ", count: 20) + "\(index)",
            body: "Distinctive content for slide \(index) and the presentation narrative.",
            notes: "Explain evidence number \(index)."
        )
    }

    var rejected = false
    do {
        _ = try LocalDeckPlanner.makePlan(
            title: "Large pitch",
            targetDurationSeconds: 180,
            slides: slides
        )
    } catch {
        rejected = true
    }
    #expect(rejected)
}

@MainActor
private func makeDelayedAIModel(
    summary: SessionSummary,
    savedRoadmap: PracticeRoadmap?,
    preferenceSuite: String
) throws -> (AppModel, VoxaDataStore) {
    let dataStore = try VoxaDataStore(inMemory: true)
    try dataStore.saveSession(
        summary: summary,
        segments: [],
        samples: [],
        cueEvents: [],
        checkpointResults: []
    )
    if let savedRoadmap {
        try dataStore.saveRoadmap(
            SavedPracticeRoadmap(
                sourceSessionID: summary.sessionID,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
                roadmap: savedRoadmap
            )
        )
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DelayedRoadmapChatURLProtocol.self]
    let apiClient = VoxaAPIClient(
        baseURL: URL(string: "https://api.example.test")!,
        bearerToken: "roadmap-chat-race-token-with-32-characters",
        session: URLSession(configuration: configuration),
        requestTimeoutSeconds: 28
    )
    let preferences = try #require(UserDefaults(suiteName: preferenceSuite))
    preferences.removePersistentDomain(forName: preferenceSuite)
    return (
        AppModel(
            dataStore: dataStore,
            speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
            cueBandClient: CueBandClient(),
            apiClient: apiClient,
            demoMode: false,
            preferences: preferences
        ),
        dataStore
    )
}

private final class DelayedAIRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func reset() {
        lock.withLock { counts = [:] }
    }

    func record(path: String) -> Int {
        lock.withLock {
            counts[path, default: 0] += 1
            return counts[path, default: 0]
        }
    }

    func count(path: String) -> Int {
        lock.withLock { counts[path, default: 0] }
    }
}

private final class DelayedRoadmapChatURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = DelayedAIRequestState()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let requestIndex = Self.state.record(path: url.path)
        let body: Data
        switch url.path {
        case "/v1/roadmaps":
            Thread.sleep(forTimeInterval: requestIndex == 1 ? 0.18 : 0.03)
            let headline = requestIndex == 1 ? "First roadmap" : "Second roadmap"
            body = Data(
                """
                {"schemaVersion":1,"headline":"\(headline)","summary":"Replace filler starts with silence while preserving a steady pace.","focusFillers":[{"phrase":"um","count":2,"guidance":"Use one quiet beat instead."}],"steps":[{"phase":"now","title":"Reset","evidence":"Two ums appeared.","action":"Pause.","measurableTarget":"One or fewer ums."},{"phase":"next","title":"Pace","evidence":"Pace was measured.","action":"Hold it.","measurableTarget":"80% in range."},{"phase":"then","title":"Voice","evidence":"Pitch was measured.","action":"Stress key words.","measurableTarget":"Practice three claims."}],"nextSessionGoal":{"title":"Cleaner opening","measurement":"Likely filler count","target":"At most one"},"confidenceNote":"Based on one finalized transcript and measured history."}
                """.utf8
            )
        case "/v1/coach-chat":
            Thread.sleep(forTimeInterval: 0.12)
            body = Data(
                #"{"schemaVersion":1,"reply":"Practice the opening with one silent beat before each claim.","suggestedPrompts":[]}"#.utf8
            )
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        guard let response = HTTPURLResponse(
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

private final class DelayedRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false

    var didStart: Bool {
        lock.withLock { started }
    }

    func reset() {
        lock.withLock { started = false }
    }

    func markStarted() {
        lock.withLock { started = true }
    }
}

private final class DelayedInsightURLProtocol: URLProtocol, @unchecked Sendable {
    static let requestGate = DelayedRequestGate()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestGate.markStarted()
        Thread.sleep(forTimeInterval: 0.12)
        let body = Data(
            #"{"schemaVersion":1,"overallSummary":"You finished on time.","strengths":[{"title":"Strong timing","evidence":"The presentation finished inside its target."}],"priorities":[{"title":"Stabilize pace","evidence":"A fast section occurred.","nextAction":"Pause after each key claim."}],"drills":[{"title":"Pace ladder","instructions":"Rehearse the opening at target pace.","durationMinutes":5}],"confidenceNote":"Feedback uses session metrics only."}"#.utf8
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

@MainActor
private func makeSessionControllerForBehaviorTests(demoMode: Bool) throws -> LiveSessionController {
    LiveSessionController(
        configuration: behaviorTestSessionConfiguration(emergencyBuzzerEnabled: false),
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        dataStore: try VoxaDataStore(inMemory: true),
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

private func behaviorTestSessionConfiguration(emergencyBuzzerEnabled: Bool) -> SessionConfiguration {
    SessionConfiguration(
        id: UUID(),
        name: "Lifecycle rehearsal",
        mode: .freeSpeaking,
        targetDurationSeconds: 120,
        profile: .rehearsalV1(),
        deckPlan: nil,
        emergencyBuzzerEnabled: emergencyBuzzerEnabled
    )
}

@MainActor
private func makeGuidedPresentationController(
    transitionCueEnabled: Bool,
    dataStore: VoxaDataStore,
    sendCue: @escaping @MainActor (CueCommand) throws -> Void
) throws -> LiveSessionController {
    let base = CoachingProfile.rehearsalV1()
    let enabledCues = transitionCueEnabled
        ? base.enabledCues.union([.deckBehind])
        : base.enabledCues.subtracting([.deckBehind])
    let profile = CoachingProfile(
        minimumWPM: base.minimumWPM,
        maximumWPM: base.maximumWPM,
        enabledCues: enabledCues,
        patternByCue: base.patternByCue,
        intensityByCue: base.intensityByCue,
        fillerClusterConfiguration: base.fillerClusterConfiguration,
        highConfidenceFillers: base.highConfidenceFillers,
        optionalFillers: base.optionalFillers
    )
    let slides = (1...3).map { index in
        DeckSlide(
            id: UUID(),
            index: index,
            title: "Slide \(index)",
            body: "",
            notes: ""
        )
    }
    let plan = try buildTimedDeckPlan(
        title: "Guided pitch",
        slides: slides,
        allocation: .even(totalSeconds: 90)
    )
    let configuration = SessionConfiguration(
        id: UUID(),
        name: "Guided pitch",
        mode: .powerPoint,
        targetDurationSeconds: 90,
        profile: profile,
        deckPlan: plan,
        emergencyBuzzerEnabled: false
    )
    return LiveSessionController(
        configuration: configuration,
        speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
        dataStore: dataStore,
        demoMode: true,
        allocateCueSequence: { 1 },
        sendCue: sendCue,
        sendSessionLight: { _ in },
        monotonicNow: { 100 },
        cueDeliveryDeadlines: CueDeliveryDeadlineConfiguration(
            acceptanceTimeoutSeconds: 2,
            completionTimeoutSeconds: 4
        ),
        onFinish: { _ in }
    )
}

private func guidedPresentationMetrics(elapsedSeconds: TimeInterval) -> LiveMetrics {
    LiveMetrics(
        elapsedSeconds: elapsedSeconds,
        rollingWPM: 145,
        finalizedWordCount: 72,
        fillerCount: 0,
        voicedSeconds: 24,
        talkRatio: 0.8,
        energyDBFS: nil,
        pitchHertz: nil
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
