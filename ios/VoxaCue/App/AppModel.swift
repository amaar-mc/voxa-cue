import AVFoundation
import Foundation
import Observation
import VoxaCore
import VoxaRuntime

enum DeckPlanSource: Equatable {
    case coachingAPI
    case local

    var label: String {
        switch self {
        case .coachingAPI: "AI prepared"
        case .local: "Prepared locally"
        }
    }
}

struct PreparedDeckPlan: Equatable {
    let plan: DeckPlan
    let source: DeckPlanSource
}

enum CoachingAPIState: Equatable {
    case localOnly
    case configured
    case checking
    case ready(build: String)
    case unavailable(message: String)
}

@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case today
        case sessions
        case insights
        case settings
    }

    let dataStore: VoxaDataStore
    let demoMode: Bool
    private let speechPipeline: LiveSpeechPipeline
    private let cueBandClient: CueBandClient
    private let apiClient: VoxaAPIClient?
    private let preferences: UserDefaults
    private var nextCueSequenceValue: UInt16
    private var includesDemoFixtures = true
    private var sessionStartTask: Task<Void, Never>?
    private var startingSessionID: UUID?

    private static let cueSequencePreferenceKey = "voxaCueNextCommandSequence"

    var selectedTab: Tab = .today
    var sessions: [SessionSummary] = []
    var connectionState: CueBandConnectionState = .idle
    var setupPresented = false
    var activeSession: LiveSessionController?
    var completedSummary: SessionSummary?
    var selectedSummary: SessionSummary?
    var insightBySession: [UUID: CoachingInsight] = [:]
    var isGeneratingInsight = false
    var coachingAPIState: CoachingAPIState
    var lastError: String?
    var usesTemporaryRecoveryStorage: Bool { dataStore.isInMemory && !demoMode }

    init(
        dataStore: VoxaDataStore,
        speechPipeline: LiveSpeechPipeline,
        cueBandClient: CueBandClient,
        apiClient: VoxaAPIClient?,
        demoMode: Bool,
        preferences: UserDefaults
    ) {
        self.dataStore = dataStore
        self.speechPipeline = speechPipeline
        self.cueBandClient = cueBandClient
        self.apiClient = apiClient
        self.demoMode = demoMode
        self.preferences = preferences
        self.coachingAPIState = apiClient == nil ? .localOnly : .configured
        let storedSequence = preferences.integer(forKey: Self.cueSequencePreferenceKey)
        self.nextCueSequenceValue = (1...Int(UInt16.max)).contains(storedSequence)
            ? UInt16(storedSequence)
            : 1
        reloadSessions()
    }

    func connectCueBand() {
        cueBandClient.connect(
            stateHandler: { [weak self] state in
                self?.connectionState = state
            },
            statusHandler: { [weak self] status in
                self?.handleBandStatus(status)
            }
        )
    }

    func disconnectCueBand() {
        cueBandClient.disconnect()
    }

    func testCue(kind: CueKind, intensity: CueIntensity) {
        do {
            try cueBandClient.send(
                command: CueCommand(
                    sequence: allocateCueSequence(),
                    kind: kind,
                    intensity: intensity,
                    repeatCount: 1
                )
            )
        } catch {
            lastError = "Connect your Cue Band before testing a vibration."
        }
    }

    func beginSession(configuration: SessionConfiguration) {
        if let activeSession, !activeSession.hasStarted {
            activeSession.cancelPreparationForLifecycle()
        }
        cancelSessionStartWork()
        let controller = LiveSessionController(
            configuration: configuration,
            speechPipeline: speechPipeline,
            dataStore: dataStore,
            semanticMatcher: SemanticMatcher(),
            demoMode: demoMode,
            allocateCueSequence: { [weak self] in
                guard let self else { return 1 }
                return self.allocateCueSequence()
            },
            sendCue: { [weak self] command in
                guard let self else { throw CueBLEError.notConnected }
                try self.cueBandClient.send(command: command)
            },
            monotonicNow: { ProcessInfo.processInfo.systemUptime },
            cueDeliveryDeadlines: .version1(),
            onFinish: { [weak self] summary in
                guard let self else { return }
                self.cancelSessionStartWork(for: summary.sessionID)
                self.completedSummary = summary
                self.activeSession = nil
                self.reloadSessions()
            }
        )
        activeSession = controller
        setupPresented = false
        startingSessionID = controller.id
        sessionStartTask = Task { [weak self, weak controller] in
            await controller?.start()
            self?.clearSessionStartWork(for: configuration.id)
        }
    }

    func handleSceneBecameInactive() {
        guard let activeSession else { return }
        if activeSession.hasStarted {
            activeSession.pauseForLifecycle()
        } else {
            cancelSessionStartWork(for: activeSession.id)
            activeSession.cancelPreparationForLifecycle()
        }
    }

    func dismissCompletedSummary() {
        completedSummary = nil
    }

    func reloadSessions() {
        let loadedSessions: [SessionSummary]
        do {
            loadedSessions = try dataStore.fetchSessions()
        } catch {
            lastError = "Your local session history could not be loaded."
            return
        }
        if demoMode, includesDemoFixtures {
            let loadedIDs = Set(loadedSessions.map(\.sessionID))
            sessions = (loadedSessions + DemoFixtures.sessions().filter { !loadedIDs.contains($0.sessionID) })
                .sorted { $0.startedAt > $1.startedAt }
        } else {
            sessions = loadedSessions
        }
        var loadedInsights: [UUID: CoachingInsight] = [:]
        var insightLoadFailed = false
        for session in sessions {
            do {
                if let insight = try dataStore.fetchInsight(sessionID: session.sessionID) {
                    loadedInsights[session.sessionID] = insight
                }
            } catch {
                insightLoadFailed = true
            }
        }
        insightBySession = loadedInsights
        if insightLoadFailed {
            lastError = "One or more saved coaching insights could not be loaded."
        }
    }

    func generateInsight(for summary: SessionSummary) async {
        if let existing = insightBySession[summary.sessionID] {
            insightBySession[summary.sessionID] = existing
            return
        }
        if let saved = try? dataStore.fetchInsight(sessionID: summary.sessionID) {
            insightBySession[summary.sessionID] = saved
            return
        }
        isGeneratingInsight = true
        defer { isGeneratingInsight = false }
        do {
            let insight: CoachingInsight
            if demoMode {
                insight = DemoFixtures.insight()
            } else if let apiClient {
                let context = try dataStore.fetchInsightContext(sessionID: summary.sessionID)
                insight = try await apiClient.createInsight(
                    summary: summary,
                    checkpoints: context.checkpoints,
                    cueEvents: context.cueEvents
                )
            } else {
                throw VoxaAPIError.invalidPayload
            }
            insightBySession[summary.sessionID] = insight
            try dataStore.saveInsight(sessionID: summary.sessionID, insight: insight)
        } catch {
            guard !Task.isCancelled, (error as? VoxaAPIError) != .cancelled else { return }
            let message = coachingErrorMessage(error)
            coachingAPIState = .unavailable(message: message)
            lastError = message
        }
    }

    func createDeckPlan(title: String, targetDurationSeconds: Int, slides: [DeckSlide]) async -> PreparedDeckPlan {
        if !demoMode, let apiClient {
            do {
                let remotePlan = try await apiClient.createDeckPlan(
                    title: title,
                    targetDurationSeconds: targetDurationSeconds,
                    slides: slides
                )
                return PreparedDeckPlan(plan: remotePlan, source: .coachingAPI)
            } catch {
                if !Task.isCancelled, (error as? VoxaAPIError) != .cancelled {
                    coachingAPIState = .unavailable(message: coachingErrorMessage(error))
                }
            }
        }
        return PreparedDeckPlan(
            plan: LocalDeckPlanner.makePlan(
                title: title,
                targetDurationSeconds: targetDurationSeconds,
                slides: slides
            ),
            source: .local
        )
    }

    func checkCoachingAPI() async {
        guard !demoMode, let apiClient else {
            coachingAPIState = .localOnly
            return
        }
        coachingAPIState = .checking
        do {
            let health = try await apiClient.readiness()
            guard health.status == "ready", health.schemaVersion == 1 else {
                coachingAPIState = .unavailable(message: "The coaching service reported that it is not ready.")
                return
            }
            coachingAPIState = .ready(build: health.build)
        } catch {
            guard !Task.isCancelled, (error as? VoxaAPIError) != .cancelled else {
                coachingAPIState = .configured
                return
            }
            coachingAPIState = .unavailable(message: coachingErrorMessage(error))
        }
    }

    func clearLocalData() {
        do {
            try dataStore.deleteAllLocalData()
            if demoMode { includesDemoFixtures = false }
            sessions = []
            insightBySession = [:]
        } catch {
            lastError = "Local data could not be deleted."
        }
    }

    private func allocateCueSequence() -> UInt16 {
        let allocated = nextCueSequenceValue
        nextCueSequenceValue = nextCueSequence(after: allocated)
        preferences.set(Int(nextCueSequenceValue), forKey: Self.cueSequencePreferenceKey)
        return allocated
    }

    private func cancelSessionStartWork() {
        sessionStartTask?.cancel()
        sessionStartTask = nil
        startingSessionID = nil
    }

    private func cancelSessionStartWork(for sessionID: UUID) {
        guard startingSessionID == sessionID else { return }
        cancelSessionStartWork()
    }

    private func clearSessionStartWork(for sessionID: UUID) {
        guard startingSessionID == sessionID else { return }
        sessionStartTask = nil
        startingSessionID = nil
    }

    private func handleBandStatus(_ status: CueBandStatus) {
        synchronizeCueSequence(after: status)
        if let activeSession {
            activeSession.handleBandStatus(status)
            return
        }
        guard status.state == .rejected || status.error != .none else { return }
        switch status.error {
        case .none:
            lastError = "The Cue Band rejected the vibration command."
        case .invalidVersion:
            lastError = "The Cue Band firmware uses an incompatible Bluetooth protocol."
        case .invalidCommand:
            lastError = "The Cue Band rejected this haptic pattern."
        case .driverFault:
            lastError = "The Cue Band haptic driver reported a hardware fault."
        }
    }

    private func synchronizeCueSequence(after status: CueBandStatus) {
        guard status.error == .none, status.state != .rejected else { return }
        let candidate = nextCueSequence(after: status.sequence)
        guard candidate != nextCueSequenceValue,
              cueSequenceIsAhead(candidate, of: nextCueSequenceValue) else {
            return
        }
        nextCueSequenceValue = candidate
        preferences.set(Int(candidate), forKey: Self.cueSequencePreferenceKey)
    }
}

private func coachingErrorMessage(_ error: any Error) -> String {
    guard let apiError = error as? VoxaAPIError else {
        return "AI coaching could not be completed. Your transcript and metrics remain safely on this iPhone."
    }
    switch apiError {
    case .cancelled:
        return "The coaching request was cancelled."
    case .timedOut:
        return "The coaching service took too long to respond. Your local results are safe; try again."
    case .offline:
        return "This iPhone appears to be offline. Local coaching metrics still work; reconnect to request AI coaching."
    case .unauthorized:
        return "The coaching service rejected this demo build’s credentials. Update the build configuration before retrying."
    case let .rateLimited(retryAfterSeconds, _):
        if let retryAfterSeconds {
            return "The coaching service is busy. Try again in about \(retryAfterSeconds) seconds."
        }
        return "The coaching service is busy. Wait a moment and try again."
    case .unavailable, .transport:
        return "The coaching service is temporarily unavailable. Your local results are safe; try again."
    case .contractMismatch:
        return "The coaching service returned an incompatible response. Update the app or API before retrying."
    case let .rejected(_, _, message, requestID):
        guard let requestID else { return message }
        return "\(message) Reference: \(requestID)"
    case .invalidPayload:
        return "This session could not be prepared for AI coaching because its local data is incomplete."
    case .invalidResponse:
        return "The coaching service returned an unreadable response. Try again."
    }
}

enum LocalDeckPlanner {
    static func makePlan(title: String, targetDurationSeconds: Int, slides: [DeckSlide]) -> DeckPlan {
        let boundedTargetDuration = max(1, targetDurationSeconds)
        let maximumCheckpointCount = min(100, boundedTargetDuration)
        let slideGroups = groupedSlides(slides, maximumGroupCount: maximumCheckpointCount)
        let weights = slideGroups.map { group in
            max(1, group.reduce(0) { total, slide in
                total + normalizedSpeechWords([slide.title, slide.body, slide.notes].joined(separator: " ")).count
            })
        }
        let totalWeight = max(1, weights.reduce(0, +))
        var cumulativeWeight = 0
        var previousTarget = 0
        let checkpoints = zip(slideGroups, weights).enumerated().compactMap { offset, pair -> DeckCheckpoint? in
            let (group, weight) = pair
            guard let representativeSlide = group.last else { return nil }
            cumulativeWeight += weight
            let remainingCheckpoints = slideGroups.count - offset - 1
            let rawTarget = Int(
                (Double(cumulativeWeight) / Double(totalWeight) * Double(boundedTargetDuration)).rounded()
            )
            let target = offset == slideGroups.count - 1
                ? boundedTargetDuration
                : min(
                    boundedTargetDuration - remainingCheckpoints,
                    max(previousTarget + 1, rawTarget)
                )
            previousTarget = target
            let combinedText = group
                .flatMap { [$0.title, $0.body, $0.notes] }
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
            let allWords = normalizedSpeechWords(combinedText)
            let anchors = Array(
                allWords
                    .filter { $0.count >= 5 }
                    .reduce(into: [String]()) { unique, word in
                        if !unique.contains(word) { unique.append(word) }
                    }
                    .prefix(6)
            )
            let fallbackAnchors = Array(["slide", "topic"].prefix(max(0, 2 - anchors.count)))
            let paddedAnchors = anchors.count >= 2 ? anchors : anchors + fallbackAnchors
            return DeckCheckpoint(
                id: "slide-\(representativeSlide.index)",
                slideIndex: representativeSlide.index,
                label: shortened(groupLabel(group), maximumCharacters: 120),
                targetCumulativeSeconds: target,
                semanticSummary: shortened(combinedText, maximumCharacters: 400),
                anchorTerms: Array(paddedAnchors)
            )
        }
        return DeckPlan(schemaVersion: 1, title: title, checkpoints: checkpoints)
    }

    static func retime(plan: DeckPlan, targetDurationSeconds: Int) -> DeckPlan {
        let boundedTargetDuration = max(1, targetDurationSeconds)
        guard !plan.checkpoints.isEmpty else { return plan }
        let maximumCheckpointCount = min(plan.checkpoints.count, boundedTargetDuration)
        let selectedCheckpoints = (0..<maximumCheckpointCount).map { index in
            let upperBound = (index + 1) * plan.checkpoints.count / maximumCheckpointCount
            return plan.checkpoints[max(0, upperBound - 1)]
        }
        let originalTarget = max(1, plan.checkpoints.last?.targetCumulativeSeconds ?? 1)
        var previousTarget = 0
        let retimedCheckpoints = selectedCheckpoints.enumerated().map { index, checkpoint in
            let remainingCheckpoints = selectedCheckpoints.count - index - 1
            let scaledTarget = Int(
                (Double(checkpoint.targetCumulativeSeconds) / Double(originalTarget)
                    * Double(boundedTargetDuration)).rounded()
            )
            let target = index == selectedCheckpoints.count - 1
                ? boundedTargetDuration
                : min(
                    boundedTargetDuration - remainingCheckpoints,
                    max(previousTarget + 1, scaledTarget)
                )
            previousTarget = target
            return DeckCheckpoint(
                id: checkpoint.id,
                slideIndex: checkpoint.slideIndex,
                label: checkpoint.label,
                targetCumulativeSeconds: target,
                semanticSummary: checkpoint.semanticSummary,
                anchorTerms: checkpoint.anchorTerms
            )
        }
        return DeckPlan(
            schemaVersion: plan.schemaVersion,
            title: plan.title,
            checkpoints: retimedCheckpoints
        )
    }

    private static func groupedSlides(_ slides: [DeckSlide], maximumGroupCount: Int) -> [[DeckSlide]] {
        guard !slides.isEmpty, maximumGroupCount > 0 else { return [] }
        let groupCount = min(slides.count, maximumGroupCount)
        return (0..<groupCount).map { groupIndex in
            let lowerBound = groupIndex * slides.count / groupCount
            let upperBound = (groupIndex + 1) * slides.count / groupCount
            return Array(slides[lowerBound..<upperBound])
        }
    }

    private static func groupLabel(_ slides: [DeckSlide]) -> String {
        guard let first = slides.first, let last = slides.last else { return "Presentation checkpoint" }
        if first.id == last.id { return first.title }
        return "\(first.title) – \(last.title)"
    }

    private static func shortened(_ value: String, maximumCharacters: Int) -> String {
        String(value.prefix(maximumCharacters))
    }
}
