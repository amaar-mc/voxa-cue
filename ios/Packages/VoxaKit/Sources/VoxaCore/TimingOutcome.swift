import Foundation

/// A session's completion timing relative to its configured target.
///
/// Sessions from 90% through 105% of the target duration, inclusive, are on target.
/// Sessions below that window are materially incomplete, while sessions above it are over target.
/// Invalid or non-finite timing values fail closed as partial and never inflate success metrics.
public enum TimingOutcome: String, Codable, Equatable, Sendable {
    case partial
    case onTarget
    case overTarget

    public static let onTargetMinimumRatio = 0.90
    public static let onTargetMaximumRatio = 1.05

    public init(durationSeconds: TimeInterval, targetDurationSeconds: TimeInterval) {
        guard durationSeconds.isFinite,
              durationSeconds >= 0,
              targetDurationSeconds.isFinite,
              targetDurationSeconds > 0 else {
            self = .partial
            return
        }
        let completionRatio = durationSeconds / targetDurationSeconds
        if completionRatio < Self.onTargetMinimumRatio {
            self = .partial
        } else if completionRatio <= Self.onTargetMaximumRatio {
            self = .onTarget
        } else {
            self = .overTarget
        }
    }
}

public extension SessionSummary {
    var timingOutcome: TimingOutcome {
        TimingOutcome(
            durationSeconds: durationSeconds,
            targetDurationSeconds: targetDurationSeconds
        )
    }
}
