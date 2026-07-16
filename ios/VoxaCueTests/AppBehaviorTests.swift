import AVFoundation
import Foundation
import Testing
import VoxaCore
import VoxaRuntime
@testable import VoxaCue

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
@Test("Demo mode never contacts the coaching API")
func demoModeAvoidsCoachingAPI() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UnexpectedRequestURLProtocol.self]
    let apiClient = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "demo-mode-must-not-send",
        session: URLSession(configuration: configuration)
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

    let plan = await model.createDeckPlan(title: "Demo pitch", targetDurationSeconds: 90, slides: slides)
    await model.generateInsight(for: summary)

    #expect(plan.checkpoints.last?.targetCumulativeSeconds == 90)
    #expect(model.insightBySession[summary.sessionID] == DemoFixtures.insight())
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
