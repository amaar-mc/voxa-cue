import Foundation

public struct ActivePresentationClock: Equatable, Sendable {
    private let startedAtReferenceSeconds: TimeInterval
    private let pausedAtReferenceSeconds: TimeInterval?
    private let accumulatedPausedSeconds: TimeInterval

    public init(startedAtReferenceSeconds: TimeInterval) {
        self.startedAtReferenceSeconds = startedAtReferenceSeconds
        self.pausedAtReferenceSeconds = nil
        self.accumulatedPausedSeconds = 0
    }

    private init(
        startedAtReferenceSeconds: TimeInterval,
        pausedAtReferenceSeconds: TimeInterval?,
        accumulatedPausedSeconds: TimeInterval
    ) {
        self.startedAtReferenceSeconds = startedAtReferenceSeconds
        self.pausedAtReferenceSeconds = pausedAtReferenceSeconds
        self.accumulatedPausedSeconds = accumulatedPausedSeconds
    }

    public var isPaused: Bool {
        pausedAtReferenceSeconds != nil
    }

    public func pausing(atReferenceSeconds referenceSeconds: TimeInterval) -> ActivePresentationClock {
        guard pausedAtReferenceSeconds == nil else { return self }
        return ActivePresentationClock(
            startedAtReferenceSeconds: startedAtReferenceSeconds,
            pausedAtReferenceSeconds: max(startedAtReferenceSeconds, referenceSeconds),
            accumulatedPausedSeconds: accumulatedPausedSeconds
        )
    }

    public func resuming(atReferenceSeconds referenceSeconds: TimeInterval) -> ActivePresentationClock {
        guard let pausedAtReferenceSeconds else { return self }
        let pausedDuration = max(0, referenceSeconds - pausedAtReferenceSeconds)
        return ActivePresentationClock(
            startedAtReferenceSeconds: startedAtReferenceSeconds,
            pausedAtReferenceSeconds: nil,
            accumulatedPausedSeconds: accumulatedPausedSeconds + pausedDuration
        )
    }

    public func elapsed(atReferenceSeconds referenceSeconds: TimeInterval) -> TimeInterval {
        let effectiveEnd = pausedAtReferenceSeconds ?? max(startedAtReferenceSeconds, referenceSeconds)
        return max(0, effectiveEnd - startedAtReferenceSeconds - accumulatedPausedSeconds)
    }
}
