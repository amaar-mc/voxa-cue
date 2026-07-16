import Foundation
import Observation
import UIKit
import VoxaCore
import VoxaRuntime

@MainActor
@Observable
final class LiveSessionController: Identifiable {
    enum Phase: Equatable {
        case preparing
        case countdown(Int)
        case recording
        case paused
        case finalizing
        case failed(String)
    }

    struct CueLog: Identifiable, Equatable {
        let id: UUID
        let sequence: UInt16
        let decision: CueDecision
        let elapsedSeconds: TimeInterval
        var deliveryStatus: CueDeliveryStatus
    }

    let id: UUID
    let configuration: SessionConfiguration
    private let speechPipeline: LiveSpeechPipeline
    private let dataStore: VoxaDataStore
    private let semanticMatcher: SemanticMatcher
    private let demoMode: Bool
    private let allocateCueSequence: @MainActor () -> UInt16
    private let sendCue: @MainActor (CueCommand) throws -> Void
    private let onFinish: @MainActor (SessionSummary) -> Void

    var phase: Phase = .preparing
    var metrics: LiveMetrics = .empty()
    var liveTranscript = ""
    var volatileTranscript = ""
    var lastCue: CueDecision?
    var cueLogs: [CueLog] = []
    var currentCheckpointLabel: String?
    var checkpointProgress: Double = 0
    var microphoneLevel: Double = 0
    var latestBandFailure: String?
    var hasStarted: Bool { startedAt != nil }

    private var startedAt: Date?
    private var presentationClock: ActivePresentationClock?
    private var timerTask: Task<Void, Never>?
    private var failureTask: Task<Void, Never>?
    private var transcriptAccumulator = TranscriptAccumulator(segments: [])
    private var timedWords: [TimedWord] = []
    private var recentFillerOffsets: [TimeInterval] = []
    private var voicedSeconds: TimeInterval = 0
    private var energyValues: [Double] = []
    private var pitchValues: [Double] = []
    private var metricSamples: [LiveMetrics] = []
    private var cueEngineState = CueEngineState.initial()
    private var currentCheckpointIndex = 0
    private var checkpointMatchStreak = 0
    private var currentCheckpointMatched = false
    private var currentCheckpointEvidenceConfidence = 0.0
    private var observedCheckpointTimes: [String: TimeInterval] = [:]
    private var observedCheckpointConfidences: [String: Double] = [:]
    private var lastStoredSampleSecond = -1

    init(
        configuration: SessionConfiguration,
        speechPipeline: LiveSpeechPipeline,
        dataStore: VoxaDataStore,
        semanticMatcher: SemanticMatcher,
        demoMode: Bool,
        allocateCueSequence: @escaping @MainActor () -> UInt16,
        sendCue: @escaping @MainActor (CueCommand) throws -> Void,
        onFinish: @escaping @MainActor (SessionSummary) -> Void
    ) {
        self.id = configuration.id
        self.configuration = configuration
        self.speechPipeline = speechPipeline
        self.dataStore = dataStore
        self.semanticMatcher = semanticMatcher
        self.demoMode = demoMode
        self.allocateCueSequence = allocateCueSequence
        self.sendCue = sendCue
        self.onFinish = onFinish
        self.currentCheckpointLabel = configuration.deckPlan?.checkpoints.first?.label
    }

    func start() async {
        phase = .preparing
        UIApplication.shared.isIdleTimerDisabled = true
        if !demoMode {
            let granted = await LiveSpeechPipeline.requestPermissions()
            guard granted else {
                phase = .failed("Microphone and speech access are required for live coaching.")
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
            do {
                try await speechPipeline.prepare(localeIdentifier: "en-US")
            } catch {
                phase = .failed("The on-device English speech model could not be prepared.")
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
        }

        for count in stride(from: 3, through: 1, by: -1) {
            phase = .countdown(count)
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
        }

        if demoMode {
            liveTranscript = "Voxa Cue gives presenters private guidance at the moment they need it, then turns each session into a focused practice plan."
        } else {
            do {
                try await speechPipeline.start { [weak self] event in
                    self?.handleSpeechEvent(event)
                }
            } catch {
                phase = .failed("The phone microphone could not start: \(error.localizedDescription)")
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
        }
        let startDate = Date()
        startedAt = startDate
        presentationClock = ActivePresentationClock(
            startedAtReferenceSeconds: startDate.timeIntervalSinceReferenceDate
        )
        phase = .recording
        timerTask = Task { [weak self] in
            await self?.runTimer()
        }
    }

    func togglePause() {
        switch phase {
        case .recording:
            let now = Date().timeIntervalSinceReferenceDate
            presentationClock = presentationClock?.pausing(atReferenceSeconds: now)
            if !demoMode { speechPipeline.pauseCapture() }
            phase = .paused
            volatileTranscript = ""
        case .paused:
            let now = Date().timeIntervalSinceReferenceDate
            presentationClock = presentationClock?.resuming(atReferenceSeconds: now)
            if !demoMode { speechPipeline.resumeCapture() }
            phase = .recording
        default:
            break
        }
    }

    func finish() async {
        guard phase != .finalizing else { return }
        let stopReference = Date().timeIntervalSinceReferenceDate
        presentationClock = presentationClock?.pausing(atReferenceSeconds: stopReference)
        phase = .finalizing
        failureTask?.cancel()
        failureTask = nil
        timerTask?.cancel()
        timerTask = nil
        if !demoMode { await speechPipeline.stop() }
        updateMetrics()
        let summary = makeSummary()
        do {
            try dataStore.saveSession(
                summary: summary,
                segments: transcriptAccumulator.segments,
                samples: metricSamples,
                cueEvents: cueLogs.map { log in
                    SessionCueEvent(
                        sequence: log.sequence,
                        kind: log.decision.kind,
                        elapsedSeconds: log.elapsedSeconds,
                        reason: log.decision.reason,
                        deliveryStatus: log.deliveryStatus
                    )
                },
                checkpointResults: makeCheckpointResults()
            )
        } catch {
            phase = .failed("The session finished, but its local summary could not be saved.")
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        UIApplication.shared.isIdleTimerDisabled = false
        onFinish(summary)
    }

    func handleBandStatus(_ status: CueBandStatus) {
        guard let index = cueLogs.firstIndex(where: { $0.sequence == status.sequence }) else { return }
        switch status.state {
        case .accepted:
            cueLogs[index].deliveryStatus = .accepted
            latestBandFailure = nil
        case .completed:
            cueLogs[index].deliveryStatus = .completed
            latestBandFailure = nil
        case .rejected:
            cueLogs[index].deliveryStatus = .failed
            switch status.error {
            case .none:
                latestBandFailure = "Cue rejected"
            case .invalidVersion:
                latestBandFailure = "Firmware mismatch"
            case .invalidCommand:
                latestBandFailure = "Cue command rejected"
            case .driverFault:
                latestBandFailure = "Haptic driver fault"
            }
        }
    }

    private func runTimer() async {
        while !Task.isCancelled {
            switch phase {
            case .recording:
                updateMetrics()
                if demoMode {
                    updateDemoMetrics()
                    updateDemoDeckAlignment()
                }
                evaluateLiveCue()
                let currentSecond = Int(metrics.elapsedSeconds)
                if currentSecond.isMultiple(of: 2), currentSecond != lastStoredSampleSecond {
                    metricSamples.append(metrics)
                    lastStoredSampleSecond = currentSecond
                }
            case .paused:
                updateMetrics()
            default:
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func handleSpeechEvent(_ event: LiveSpeechEvent) {
        switch event {
        case let .volatileTranscript(text, _, _):
            guard phase == .recording else { return }
            volatileTranscript = text
        case let .finalizedTranscript(text, startSeconds, endSeconds):
            guard phase == .recording || phase == .paused || phase == .finalizing else { return }
            let segment = FinalTranscriptSegment(
                id: UUID(),
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                text: text
            )
            transcriptAccumulator = transcriptAccumulator.inserting(segment)
            liveTranscript = transcriptAccumulator.transcript
            volatileTranscript = ""
            rebuildTranscriptMetrics()
            updateDeckAlignment()
        case let .voiceActivity(isSpeech, durationSeconds):
            guard phase == .recording || phase == .paused || phase == .finalizing else { return }
            if isSpeech { voicedSeconds += durationSeconds }
        case let .vocalSample(energyDBFS, pitchHertz):
            guard phase == .recording || phase == .paused || phase == .finalizing else { return }
            energyValues.append(energyDBFS)
            if let pitchHertz { pitchValues.append(pitchHertz) }
            microphoneLevel = min(1, max(0, (energyDBFS + 60) / 50))
        case let .failure(message):
            guard phase == .recording || phase == .paused else { return }
            let stopReference = Date().timeIntervalSinceReferenceDate
            presentationClock = presentationClock?.pausing(atReferenceSeconds: stopReference)
            timerTask?.cancel()
            timerTask = nil
            phase = .finalizing
            failureTask = Task { [weak self] in
                guard let self else { return }
                await speechPipeline.stop()
                updateMetrics()
                UIApplication.shared.isIdleTimerDisabled = false
                phase = .failed("Live analysis stopped: \(message) You can save the completed portion of this session.")
                failureTask = nil
            }
        }
    }

    private func rebuildTranscriptMetrics() {
        timedWords = transcriptAccumulator.segments.flatMap { segment in
            let words = normalizedSpeechWords(segment.text)
            guard !words.isEmpty else { return [TimedWord]() }
            let duration = max(0.01, segment.endSeconds - segment.startSeconds)
            return words.enumerated().map { index, word in
                let fraction = Double(index + 1) / Double(words.count)
                return TimedWord(text: word, endSeconds: segment.startSeconds + duration * fraction)
            }
        }
        recentFillerOffsets = timedFillerOffsets(
            segments: transcriptAccumulator.segments,
            fillers: configuration.profile.highConfidenceFillers
        )
    }

    private func updateMetrics() {
        guard let presentationClock else { return }
        let elapsed = presentationClock.elapsed(atReferenceSeconds: Date().timeIntervalSinceReferenceDate)
        let transcriptAnalysis = analyzeTranscript(
            transcriptAccumulator.transcript,
            fillers: configuration.profile.highConfidenceFillers
        )
        metrics = LiveMetrics(
            elapsedSeconds: elapsed,
            rollingWPM: rollingWordsPerMinute(words: timedWords, nowSeconds: elapsed, windowSeconds: 20),
            finalizedWordCount: transcriptAnalysis.words.count,
            fillerCount: transcriptAnalysis.fillerCount,
            voicedSeconds: voicedSeconds,
            talkRatio: computedTalkRatio(voicedSeconds: voicedSeconds, elapsedSeconds: elapsed),
            energyDBFS: energyValues.last,
            pitchHertz: pitchValues.last
        )
    }

    private func updateDemoMetrics() {
        let elapsed = metrics.elapsedSeconds
        let wordCount = max(24, Int(elapsed * 2.45))
        let fillerCount = elapsed > 42 ? 2 : (elapsed > 18 ? 1 : 0)
        metrics = LiveMetrics(
            elapsedSeconds: elapsed,
            rollingWPM: 147 + sin(elapsed / 8) * 7,
            finalizedWordCount: wordCount,
            fillerCount: fillerCount,
            voicedSeconds: elapsed * 0.78,
            talkRatio: 0.78,
            energyDBFS: -24 + sin(elapsed / 4) * 3,
            pitchHertz: 178 + sin(elapsed / 3) * 18
        )
        recentFillerOffsets = fillerCount == 2 ? [max(0, elapsed - 6), max(0, elapsed - 2)] : []
        microphoneLevel = 0.58 + sin(elapsed * 2) * 0.12
    }

    private func updateDemoDeckAlignment() {
        guard let checkpoints = configuration.deckPlan?.checkpoints else { return }
        while currentCheckpointIndex < checkpoints.count {
            let checkpoint = checkpoints[currentCheckpointIndex]
            guard metrics.elapsedSeconds >= TimeInterval(checkpoint.targetCumulativeSeconds) else { break }
            observedCheckpointTimes[checkpoint.id] = metrics.elapsedSeconds
            observedCheckpointConfidences[checkpoint.id] = 1
            currentCheckpointIndex += 1
        }
        checkpointProgress = checkpoints.isEmpty ? 0 : Double(currentCheckpointIndex) / Double(checkpoints.count)
        currentCheckpointLabel = currentCheckpointIndex < checkpoints.count
            ? checkpoints[currentCheckpointIndex].label
            : "Deck complete"
    }

    private func updateDeckAlignment() {
        guard let checkpoints = configuration.deckPlan?.checkpoints,
              currentCheckpointIndex < checkpoints.count else {
            checkpointProgress = 1
            currentCheckpointLabel = "Deck complete"
            return
        }
        let checkpoint = checkpoints[currentCheckpointIndex]
        let recentText = String(liveTranscript.suffix(900))
        let similarity = semanticMatcher.similarity(first: recentText, second: checkpoint.semanticSummary)
        let match = matchDeckCheckpoint(
            DeckMatchInput(transcript: recentText, checkpoint: checkpoint, semanticSimilarity: similarity)
        )
        currentCheckpointMatched = match.reached
        currentCheckpointEvidenceConfidence = min(
            1,
            Double(normalizedSpeechWords(recentText).count) / 40
        )
        checkpointMatchStreak = match.reached ? checkpointMatchStreak + 1 : 0
        if checkpointMatchStreak >= 2 {
            observedCheckpointTimes[checkpoint.id] = metrics.elapsedSeconds
            observedCheckpointConfidences[checkpoint.id] = match.combinedScore
            currentCheckpointIndex += 1
            checkpointMatchStreak = 0
            currentCheckpointMatched = false
            currentCheckpointEvidenceConfidence = 0
        }
        checkpointProgress = checkpoints.isEmpty ? 0 : Double(currentCheckpointIndex) / Double(checkpoints.count)
        currentCheckpointLabel = currentCheckpointIndex < checkpoints.count
            ? checkpoints[currentCheckpointIndex].label
            : "Deck complete"
    }

    private func evaluateLiveCue() {
        let deckProgress: DeckProgress?
        if let checkpoints = configuration.deckPlan?.checkpoints,
           currentCheckpointIndex < checkpoints.count {
            let checkpoint = checkpoints[currentCheckpointIndex]
            deckProgress = DeckProgress(
                checkpointID: checkpoint.id,
                targetCumulativeSeconds: TimeInterval(checkpoint.targetCumulativeSeconds),
                reached: currentCheckpointMatched,
                confidence: currentCheckpointEvidenceConfidence
            )
        } else {
            deckProgress = nil
        }
        let input = CueEvaluationInput(
            metrics: metrics,
            targetDurationSeconds: configuration.targetDurationSeconds,
            recentFillerOffsets: recentFillerOffsets,
            deckProgress: deckProgress,
            profile: configuration.profile,
            isPaused: phase == .paused
        )
        let result = evaluateCue(input: input, state: cueEngineState, configuration: .version1())
        cueEngineState = result.state
        guard let decision = result.decision else { return }
        lastCue = decision
        let sequence = allocateCueSequence()
        let intensity = configuration.profile.intensityByCue[decision.kind] ?? .medium
        let command = CueCommand(sequence: sequence, kind: decision.kind, intensity: intensity, repeatCount: 1)
        var deliveryStatus = CueDeliveryStatus.pending
        do {
            try sendCue(command)
        } catch {
            deliveryStatus = .notConnected
        }
        cueLogs.append(
            CueLog(
                id: UUID(),
                sequence: sequence,
                decision: decision,
                elapsedSeconds: metrics.elapsedSeconds,
                deliveryStatus: deliveryStatus
            )
        )
    }

    private func makeSummary() -> SessionSummary {
        let duration = max(1, metrics.elapsedSeconds)
        let wordCount = demoMode ? metrics.finalizedWordCount : normalizedSpeechWords(liveTranscript).count
        let fillers = demoMode
            ? metrics.fillerCount
            : analyzeTranscript(liveTranscript, fillers: configuration.profile.highConfidenceFillers).fillerCount
        let paceSamples = metricSamples.filter { $0.rollingWPM > 0 }
        let inRange = paceSamples.filter {
            $0.rollingWPM >= configuration.profile.minimumWPM && $0.rollingWPM <= configuration.profile.maximumWPM
        }.count
        let speakingSeconds = min(duration, max(0, metrics.voicedSeconds))
        return SessionSummary(
            sessionID: id,
            name: configuration.name,
            startedAt: startedAt ?? Date(),
            durationSeconds: duration,
            targetDurationSeconds: configuration.targetDurationSeconds,
            targetMinimumWPM: configuration.profile.minimumWPM,
            targetMaximumWPM: configuration.profile.maximumWPM,
            speakingSeconds: speakingSeconds,
            averageWPM: Double(wordCount) * 60 / duration,
            timeInPaceRange: paceSamples.isEmpty ? 0 : Double(inRange) / Double(paceSamples.count),
            fillerCount: fillers,
            fillersPerSpeakingMinute: speakingSeconds > 0 ? Double(fillers) * 60 / speakingSeconds : 0,
            talkRatio: computedTalkRatio(voicedSeconds: speakingSeconds, elapsedSeconds: duration),
            pitchRangeSemitones: demoMode ? 7.2 : pitchRangeSemitones(pitches: pitchValues),
            energyRangeDB: demoMode ? 13.1 : energyRangeDB(values: energyValues),
            cueCount: cueLogs.filter { $0.deliveryStatus == .completed || $0.deliveryStatus == .accepted }.count,
            transcript: liveTranscript
        )
    }

    private func makeCheckpointResults() -> [SessionCheckpointResult] {
        guard let checkpoints = configuration.deckPlan?.checkpoints else { return [] }
        return checkpoints.map { checkpoint in
            let observed = observedCheckpointTimes[checkpoint.id]
            let status: CheckpointOutcomeStatus
            if observed != nil {
                status = .reached
            } else if metrics.elapsedSeconds >= TimeInterval(checkpoint.targetCumulativeSeconds) {
                status = .missed
            } else {
                status = .skipped
            }
            return SessionCheckpointResult(
                id: checkpoint.id,
                label: checkpoint.label,
                targetCumulativeSeconds: checkpoint.targetCumulativeSeconds,
                observedCumulativeSeconds: observed,
                confidence: observedCheckpointConfidences[checkpoint.id],
                status: status
            )
        }
    }
}
