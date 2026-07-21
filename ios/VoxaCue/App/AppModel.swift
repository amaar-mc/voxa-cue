import AVFoundation
import Foundation
import Observation
import VoxaCore
import VoxaRuntime

enum CoachingAPIState: Equatable {
    case localOnly
    case configured
    case checking
    case ready(build: String)
    case unavailable(message: String)
}

enum OnboardingPresentation: Equatable {
    case firstRun
    case replay
}

enum SessionSetupIntent: Equatable {
    case freeSpeaking
    case presentation

    var mode: SessionMode {
        switch self {
        case .freeSpeaking: .freeSpeaking
        case .presentation: .powerPoint
        }
    }
}

func normalizedHapticPreferences(
    _ stored: HapticPreferences,
    defaults: HapticPreferences
) -> HapticPreferences {
    let patterns = defaults.patternByCue.merging(stored.patternByCue) { _, storedPattern in
        storedPattern
    }
    let intensities = defaults.intensityByCue.merging(stored.intensityByCue) { _, storedIntensity in
        storedIntensity
    }
    let enabledCues = stored.enabledCues.filter { cue in
        patterns[cue] != nil && intensities[cue] != nil
    }
    return HapticPreferences(
        enabledCues: enabledCues,
        patternByCue: patterns,
        intensityByCue: intensities,
        fillerClusterConfiguration: stored.fillerClusterConfiguration
    )
}

enum DeviceLabCueDelivery: Equatable {
    case idle
    case awaitingAcceptance(sequence: UInt16)
    case awaitingCompletion(sequence: UInt16)
    case completed(sequence: UInt16)
    case rejected(sequence: UInt16, error: CueBandCommandError)
    case failed(sequence: UInt16, message: String)

    var isPending: Bool {
        switch self {
        case .awaitingAcceptance, .awaitingCompletion: true
        case .idle, .completed, .rejected, .failed: false
        }
    }

    var pendingSequence: UInt16? {
        switch self {
        case let .awaitingAcceptance(sequence), let .awaitingCompletion(sequence): sequence
        case .idle, .completed, .rejected, .failed: nil
        }
    }

    var label: String {
        switch self {
        case .idle: "No test sent"
        case .awaitingAcceptance: "Sending"
        case .awaitingCompletion: "Accepted"
        case .completed: "Completed"
        case .rejected: "Rejected"
        case .failed: "Failed"
        }
    }

    var failureMessage: String? {
        if case let .failed(_, message) = self { return message }
        return nil
    }
}

func reduceDeviceLabCueDelivery(
    _ delivery: DeviceLabCueDelivery,
    status: CueBandStatus
) -> DeviceLabCueDelivery {
    guard delivery.pendingSequence == status.sequence else { return delivery }
    let phase: CueBandAcknowledgementPhase
    switch delivery {
    case .awaitingAcceptance:
        phase = .awaitingAcceptance
    case .awaitingCompletion:
        phase = .awaitingCompletion
    case .idle, .completed, .rejected, .failed:
        return delivery
    }
    switch advanceCueBandAcknowledgement(phase, with: status) {
    case .awaitingAcceptance:
        return delivery
    case .awaitingCompletion:
        return .awaitingCompletion(sequence: status.sequence)
    case .completed:
        return .completed(sequence: status.sequence)
    case let .failed(failure):
        switch failure {
        case .completionBeforeAcceptance:
            return .failed(sequence: status.sequence, message: "Completion arrived before acceptance.")
        case let .rejected(error), let .statusError(error):
            return .rejected(sequence: status.sequence, error: error)
        }
    }
}

func reduceDeviceLabCueDelivery(
    _ delivery: DeviceLabCueDelivery,
    connectionState: CueBandConnectionState
) -> DeviceLabCueDelivery {
    guard let sequence = delivery.pendingSequence else { return delivery }
    switch connectionState {
    case let .failed(message):
        return .failed(sequence: sequence, message: "Bluetooth failed: \(message)")
    case .bluetoothUnavailable:
        return .failed(
            sequence: sequence,
            message: "Bluetooth became unavailable before the haptic was confirmed."
        )
    case .idle:
        return .failed(
            sequence: sequence,
            message: "The Cue Band disconnected before the haptic was confirmed."
        )
    case .searching, .connecting, .discovering, .ready, .reconnecting:
        return delivery
    }
}

func failDeviceLabCueDeliveryOnTimeout(_ delivery: DeviceLabCueDelivery) -> DeviceLabCueDelivery {
    switch delivery {
    case let .awaitingAcceptance(sequence):
        return .failed(sequence: sequence, message: "Timed out waiting for the command to be accepted.")
    case let .awaitingCompletion(sequence):
        return .failed(
            sequence: sequence,
            message: "The command was accepted, but vibration completion was not confirmed."
        )
    case .idle, .completed, .rejected, .failed:
        return delivery
    }
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
    let proEntitlementStore: ProEntitlementStore
    private let speechPipeline: LiveSpeechPipeline
    private let cueBandClient: CueBandClient
    private let apiClient: VoxaAPIClient?
    private let preferences: UserDefaults
    private var nextCueSequenceValue: UInt16
    private var includesDemoFixtures = true
    private var deletedSessionIDs: Set<UUID> = []
    private var sessionStartTask: Task<Void, Never>?
    private var startingSessionID: UUID?
    private var deviceLabTimeoutTask: Task<Void, Never>?
    private var pendingSession: LiveSessionController?
    private var roadmapGenerationID: UUID?
    private var coachConversationID = UUID()

    private static let cueSequencePreferenceKey = "voxaCueNextCommandSequence"
    private static let hapticPreferencesKey = "voxaCueHapticPreferencesV1"
    private static let onboardingCompletionPreferenceKey = "hasCompletedVoxaOnboarding"

    var selectedTab: Tab = .today
    var sessions: [SessionSummary] = []
    var connectionState: CueBandConnectionState = .idle
    var discoveredBand: CueBandIdentity?
    var lastBandStatus: CueBandStatus?
    var lastWriteRequestPacket: Data?
    var lastReceivedBandPacket: Data?
    var deviceLabCueDelivery = DeviceLabCueDelivery.idle
    var setupPresented = false
    var sessionSetupIntent = SessionSetupIntent.freeSpeaking
    var activeSession: LiveSessionController?
    var completedSummary: SessionSummary?
    var selectedSummary: SessionSummary?
    var insightBySession: [UUID: CoachingInsight] = [:]
    var isGeneratingInsight = false
    var practiceRoadmap: SavedPracticeRoadmap?
    var isGeneratingRoadmap = false
    var coachMessages: [CoachMessage] = []
    var isSendingCoachMessage = false
    var coachingAPIState: CoachingAPIState
    var onboardingPresentation: OnboardingPresentation?
    var hapticPreferences: HapticPreferences {
        didSet { persistHapticPreferences() }
    }
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
        self.onboardingPresentation = preferences.bool(forKey: Self.onboardingCompletionPreferenceKey)
            ? nil
            : .firstRun
        self.proEntitlementStore = ProEntitlementStore(
            preferences: preferences,
            productID: ProEntitlementStore.monthlyProductID,
            allowsDemoAccess: Self.prototypeProAccessIsEnabled
        )
        self.coachingAPIState = apiClient == nil ? .localOnly : .configured
        let defaultHaptics = HapticPreferences.defaultsV1()
        let storedHaptics = preferences.data(forKey: Self.hapticPreferencesKey)
            .flatMap { try? JSONDecoder().decode(HapticPreferences.self, from: $0) }
            ?? defaultHaptics
        self.hapticPreferences = normalizedHapticPreferences(
            storedHaptics,
            defaults: defaultHaptics
        )
        let storedSequence = preferences.integer(forKey: Self.cueSequencePreferenceKey)
        self.nextCueSequenceValue = (1...Int(UInt16.max)).contains(storedSequence)
            ? UInt16(storedSequence)
            : 1
        persistHapticPreferences()
        reloadSessions()
    }

    private static var prototypeProAccessIsEnabled: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    func connectCueBand() {
        clearDeviceLabTelemetry()
        discoveredBand = nil
        cueBandClient.connect(
            stateHandler: { [weak self] state in
                self?.handleCueBandConnectionState(state)
            },
            statusHandler: { [weak self] status in
                self?.handleBandStatus(status)
            },
            packetHandler: { [weak self] packet in
                self?.handleBandPacket(packet)
            },
            discoveryHandler: { [weak self] identity in
                self?.discoveredBand = identity
            }
        )
    }

    func disconnectCueBand() {
        cueBandClient.disconnect()
        discoveredBand = nil
        clearDeviceLabTelemetry()
    }

    func sendDebugCue(pattern: HapticPattern, intensity: CueIntensity, repeatCount: UInt8) {
        clearDeviceLabTelemetry()
        let sequence = allocateCueSequence()
        deviceLabCueDelivery = .awaitingAcceptance(sequence: sequence)
        scheduleDeviceLabTimeout(sequence: sequence)
        do {
            try cueBandClient.send(
                command: CueCommand(
                    sequence: sequence,
                    pattern: pattern,
                    intensity: intensity,
                    repeatCount: repeatCount
                )
            )
        } catch {
            deviceLabTimeoutTask?.cancel()
            deviceLabTimeoutTask = nil
            deviceLabCueDelivery = .failed(sequence: sequence, message: "The command could not be written.")
            lastError = "The debug command was not sent. Connect the Cue Band and use a repeat count from 1 to 3."
        }
    }

    func setCueEnabled(_ cue: CueKind, enabled: Bool) {
        var enabledCues = hapticPreferences.enabledCues
        if enabled {
            enabledCues.insert(cue)
        } else {
            enabledCues.remove(cue)
        }
        hapticPreferences = HapticPreferences(
            enabledCues: enabledCues,
            patternByCue: hapticPreferences.patternByCue,
            intensityByCue: hapticPreferences.intensityByCue,
            fillerClusterConfiguration: hapticPreferences.fillerClusterConfiguration
        )
    }

    func setCuePattern(_ cue: CueKind, pattern: HapticPattern) {
        var patterns = hapticPreferences.patternByCue
        patterns[cue] = pattern
        hapticPreferences = HapticPreferences(
            enabledCues: hapticPreferences.enabledCues,
            patternByCue: patterns,
            intensityByCue: hapticPreferences.intensityByCue,
            fillerClusterConfiguration: hapticPreferences.fillerClusterConfiguration
        )
    }

    func setCueIntensity(_ cue: CueKind, intensity: CueIntensity) {
        var intensities = hapticPreferences.intensityByCue
        intensities[cue] = intensity
        hapticPreferences = HapticPreferences(
            enabledCues: hapticPreferences.enabledCues,
            patternByCue: hapticPreferences.patternByCue,
            intensityByCue: intensities,
            fillerClusterConfiguration: hapticPreferences.fillerClusterConfiguration
        )
    }

    func setFillerClusterConfiguration(_ configuration: FillerClusterConfiguration) {
        hapticPreferences = HapticPreferences(
            enabledCues: hapticPreferences.enabledCues,
            patternByCue: hapticPreferences.patternByCue,
            intensityByCue: hapticPreferences.intensityByCue,
            fillerClusterConfiguration: configuration
        )
    }

    func restoreDefaultHaptics() {
        hapticPreferences = .defaultsV1()
    }

    func presentOnboarding() {
        onboardingPresentation = .replay
    }

    func skipOnboarding() {
        persistOnboardingCompletion()
        onboardingPresentation = nil
    }

    func completeOnboarding(setupIntent: SessionSetupIntent?) {
        persistOnboardingCompletion()
        onboardingPresentation = nil
        if let setupIntent {
            selectedTab = .today
            presentSessionSetup(intent: setupIntent)
        }
    }

    func presentSessionSetup(intent: SessionSetupIntent) {
        guard cueBandIsReady else {
            setupPresented = false
            selectedTab = .today
            lastError = "Connect your Cue Band before setting up a session."
            return
        }
        lastError = nil
        sessionSetupIntent = intent
        setupPresented = true
    }

    var cueBandIsReady: Bool {
        if case .ready = connectionState { return true }
        return false
    }

    func beginSession(configuration: SessionConfiguration) {
        if let activeSession, !activeSession.hasStarted {
            activeSession.cancelPreparationForLifecycle()
        }
        pendingSession?.cancelPreparationForLifecycle()
        pendingSession = nil
        cancelSessionStartWork()
        let controller = LiveSessionController(
            configuration: configuration,
            speechPipeline: speechPipeline,
            dataStore: dataStore,
            demoMode: demoMode,
            allocateCueSequence: { [weak self] in
                guard let self else { return 1 }
                return self.allocateCueSequence()
            },
            sendCue: { [weak self] command in
                guard let self else { throw CueBLEError.notConnected }
                try self.cueBandClient.send(command: command)
            },
            sendSessionLight: { [weak self] sessionLight in
                guard let self else { throw CueBLEError.notConnected }
                try self.cueBandClient.send(sessionLight: sessionLight)
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
        if setupPresented {
            pendingSession = controller
            setupPresented = false
        } else {
            activateSession(controller)
        }
    }

    func presentPendingSession() {
        guard let pendingSession else { return }
        self.pendingSession = nil
        activateSession(pendingSession)
    }

    private func activateSession(_ controller: LiveSessionController) {
        activeSession = controller
        let sessionID = controller.id
        startingSessionID = sessionID
        sessionStartTask = Task { [weak self, weak controller] in
            await controller?.start()
            self?.clearSessionStartWork(for: sessionID)
        }
    }

    func handleSceneBecameInactive() {
        guard let activeSession else { return }
        if activeSession.hasStarted {
            activeSession.pauseForLifecycle()
            return
        }
        guard case .countdown = activeSession.phase else { return }
        cancelSessionStartWork(for: activeSession.id)
        activeSession.cancelPreparationForLifecycle()
    }

    func handleSceneEnteredBackground() {
        guard let activeSession else { return }
        if activeSession.hasStarted {
            activeSession.pauseForLifecycle()
            return
        }
        cancelSessionStartWork(for: activeSession.id)
        activeSession.cancelPreparationForLifecycle()
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
        let retainedSessions = loadedSessions.filter { !deletedSessionIDs.contains($0.sessionID) }
        if demoMode, includesDemoFixtures {
            let loadedIDs = Set(retainedSessions.map(\.sessionID))
            sessions = (
                retainedSessions
                    + DemoFixtures.sessions().filter {
                        !loadedIDs.contains($0.sessionID) && !deletedSessionIDs.contains($0.sessionID)
                    }
            )
                .sorted { $0.startedAt > $1.startedAt }
        } else {
            sessions = retainedSessions
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
        do {
            let savedRoadmap = try dataStore.fetchLatestRoadmap()
            practiceRoadmap = savedRoadmap.flatMap { snapshot in
                sessions.contains(where: { $0.sessionID == snapshot.sourceSessionID }) ? snapshot : nil
            }
        } catch {
            practiceRoadmap = nil
            lastError = "Your saved practice roadmap could not be loaded."
        }
    }

    func generateInsight(for summary: SessionSummary) async {
        guard !deletedSessionIDs.contains(summary.sessionID),
              sessions.contains(where: { $0.sessionID == summary.sessionID }) else {
            return
        }
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
            guard !deletedSessionIDs.contains(summary.sessionID),
                  sessions.contains(where: { $0.sessionID == summary.sessionID }) else {
                return
            }
            try dataStore.saveInsight(sessionID: summary.sessionID, insight: insight)
            insightBySession[summary.sessionID] = insight
        } catch {
            guard !Task.isCancelled, (error as? VoxaAPIError) != .cancelled else { return }
            let message = coachingErrorMessage(error)
            coachingAPIState = .unavailable(message: message)
            lastError = message
        }
    }

    func generateRoadmap(for summary: SessionSummary) async {
        guard !deletedSessionIDs.contains(summary.sessionID),
              sessions.contains(where: { $0.sessionID == summary.sessionID }),
              !summary.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let generationID = UUID()
        roadmapGenerationID = generationID
        isGeneratingRoadmap = true
        defer {
            if roadmapGenerationID == generationID {
                roadmapGenerationID = nil
                isGeneratingRoadmap = false
            }
        }
        do {
            let roadmap: PracticeRoadmap
            if demoMode {
                roadmap = DemoFixtures.roadmap()
            } else if let apiClient {
                let profile = CoachingProfile.rehearsalV1()
                let fillerBreakdown = presentationFillerBreakdown(
                    summary.transcript,
                    highConfidenceFillers: profile.highConfidenceFillers,
                    contextualFillers: profile.optionalFillers
                )
                roadmap = try await apiClient.createRoadmap(
                    summary: summary,
                    history: makeLongTermAnalytics(sessions: sessions),
                    fillerBreakdown: fillerBreakdown
                )
            } else {
                throw VoxaAPIError.invalidPayload
            }
            guard roadmapGenerationID == generationID,
                  !deletedSessionIDs.contains(summary.sessionID),
                  sessions.contains(where: { $0.sessionID == summary.sessionID }) else {
                return
            }
            let snapshot = SavedPracticeRoadmap(
                sourceSessionID: summary.sessionID,
                generatedAt: Date(),
                roadmap: roadmap
            )
            try dataStore.saveRoadmap(snapshot)
            practiceRoadmap = snapshot
            clearCoachConversation()
        } catch {
            guard roadmapGenerationID == generationID,
                  !Task.isCancelled,
                  (error as? VoxaAPIError) != .cancelled else {
                return
            }
            let message = coachingErrorMessage(error)
            coachingAPIState = .unavailable(message: message)
            lastError = message
        }
    }

    func sendCoachMessage(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 1_000,
              !isSendingCoachMessage,
              let snapshot = practiceRoadmap,
              let summary = sessions.first(where: { $0.sessionID == snapshot.sourceSessionID }),
              !deletedSessionIDs.contains(summary.sessionID) else {
            return
        }
        let userMessage = CoachMessage(id: UUID(), role: .user, content: trimmed)
        coachMessages = Array((coachMessages + [userMessage]).suffix(10))
        let boundedMessages = coachMessages
        let conversationID = coachConversationID
        isSendingCoachMessage = true
        defer {
            if coachConversationID == conversationID {
                isSendingCoachMessage = false
            }
        }
        do {
            let reply: CoachReply
            if demoMode {
                reply = CoachReply(
                    schemaVersion: 1,
                    reply: "For the next rehearsal, focus on the first minute: replace filler starts with a quiet beat and aim to stay inside your selected pace range.",
                    suggestedPrompts: ["Give me a two-minute drill", "How should I open?"]
                )
            } else if let apiClient {
                let profile = CoachingProfile.rehearsalV1()
                reply = try await apiClient.sendCoachMessage(
                    summary: summary,
                    fillerBreakdown: presentationFillerBreakdown(
                        summary.transcript,
                        highConfidenceFillers: profile.highConfidenceFillers,
                        contextualFillers: profile.optionalFillers
                    ),
                    roadmap: snapshot.roadmap,
                    messages: boundedMessages
                )
            } else {
                throw VoxaAPIError.invalidPayload
            }
            guard coachConversationID == conversationID,
                  practiceRoadmap?.sourceSessionID == summary.sessionID,
                  !deletedSessionIDs.contains(summary.sessionID) else {
                return
            }
            coachMessages = Array(
                (coachMessages + [CoachMessage(id: UUID(), role: .assistant, content: reply.reply)])
                    .suffix(10)
            )
        } catch {
            guard coachConversationID == conversationID,
                  !Task.isCancelled,
                  (error as? VoxaAPIError) != .cancelled else {
                return
            }
            lastError = coachingErrorMessage(error)
        }
    }

    func clearCoachConversation() {
        coachConversationID = UUID()
        coachMessages = []
        isSendingCoachMessage = false
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
            deletedSessionIDs.formUnion(sessions.map(\.sessionID))
            sessions = []
            insightBySession = [:]
            roadmapGenerationID = nil
            isGeneratingRoadmap = false
            practiceRoadmap = nil
            clearCoachConversation()
        } catch {
            lastError = "Local data could not be deleted."
        }
    }

    func deleteSession(_ summary: SessionSummary) {
        do {
            try dataStore.deleteSession(sessionID: summary.sessionID)
            deletedSessionIDs.insert(summary.sessionID)
            sessions.removeAll { $0.sessionID == summary.sessionID }
            insightBySession.removeValue(forKey: summary.sessionID)
            roadmapGenerationID = nil
            isGeneratingRoadmap = false
            practiceRoadmap = nil
            clearCoachConversation()
            if selectedSummary?.sessionID == summary.sessionID {
                selectedSummary = nil
            }
            if completedSummary?.sessionID == summary.sessionID {
                completedSummary = nil
            }
        } catch {
            lastError = "This session could not be deleted."
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

    private func handleCueBandConnectionState(_ state: CueBandConnectionState) {
        let wasReady: Bool
        if case .ready = connectionState {
            wasReady = true
        } else {
            wasReady = false
        }
        connectionState = state
        if case .ready = state, !wasReady {
            activeSession?.resendSessionLight()
        }
        let reduced = reduceDeviceLabCueDelivery(deviceLabCueDelivery, connectionState: state)
        guard reduced != deviceLabCueDelivery else { return }
        deviceLabCueDelivery = reduced
        deviceLabTimeoutTask?.cancel()
        deviceLabTimeoutTask = nil
    }

    private func handleBandStatus(_ status: CueBandStatus) {
        lastBandStatus = status
        synchronizeCueSequence(after: status)
        if let activeSession {
            activeSession.handleBandStatus(status)
            return
        }
        deviceLabCueDelivery = reduceDeviceLabCueDelivery(deviceLabCueDelivery, status: status)
        if !deviceLabCueDelivery.isPending {
            deviceLabTimeoutTask?.cancel()
            deviceLabTimeoutTask = nil
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

    private func handleBandPacket(_ packet: CueBandPacket) {
        switch packet.direction {
        case .writeRequested:
            lastWriteRequestPacket = packet.data
        case .received:
            lastReceivedBandPacket = packet.data
        }
    }

    private func clearDeviceLabTelemetry() {
        deviceLabTimeoutTask?.cancel()
        deviceLabTimeoutTask = nil
        deviceLabCueDelivery = .idle
        lastBandStatus = nil
        lastWriteRequestPacket = nil
        lastReceivedBandPacket = nil
    }

    private func persistHapticPreferences() {
        guard let encoded = try? JSONEncoder().encode(hapticPreferences) else { return }
        preferences.set(encoded, forKey: Self.hapticPreferencesKey)
    }

    private func persistOnboardingCompletion() {
        preferences.set(true, forKey: Self.onboardingCompletionPreferenceKey)
    }

    private func scheduleDeviceLabTimeout(sequence: UInt16) {
        deviceLabTimeoutTask?.cancel()
        deviceLabTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            guard let self,
                  self.deviceLabCueDelivery.pendingSequence == sequence else {
                return
            }
            self.deviceLabCueDelivery = failDeviceLabCueDeliveryOnTimeout(self.deviceLabCueDelivery)
            self.deviceLabTimeoutTask = nil
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
