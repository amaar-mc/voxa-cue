import Foundation

public struct CueDeliveryDeadlineConfiguration: Equatable, Sendable {
    public let acceptanceTimeoutSeconds: TimeInterval
    public let completionTimeoutSeconds: TimeInterval

    public init(acceptanceTimeoutSeconds: TimeInterval, completionTimeoutSeconds: TimeInterval) {
        precondition(acceptanceTimeoutSeconds > 0)
        precondition(completionTimeoutSeconds > 0)
        self.acceptanceTimeoutSeconds = acceptanceTimeoutSeconds
        self.completionTimeoutSeconds = completionTimeoutSeconds
    }

    public static func version1() -> CueDeliveryDeadlineConfiguration {
        CueDeliveryDeadlineConfiguration(
            acceptanceTimeoutSeconds: 2,
            completionTimeoutSeconds: 4
        )
    }
}

public enum CueDeliveryDeadlineEvaluation: Equatable, Sendable {
    case unchanged(CueDeliveryStatus)
    case failedAwaitingAcceptance
    case failedAwaitingCompletion
}

public func evaluateCueDeliveryDeadline(
    status: CueDeliveryStatus,
    sentAtMonotonicSeconds: TimeInterval,
    acceptedAtMonotonicSeconds: TimeInterval?,
    nowMonotonicSeconds: TimeInterval,
    configuration: CueDeliveryDeadlineConfiguration
) -> CueDeliveryDeadlineEvaluation {
    if status == .pending,
       nowMonotonicSeconds - sentAtMonotonicSeconds >= configuration.acceptanceTimeoutSeconds {
        return .failedAwaitingAcceptance
    }
    if status == .accepted,
       nowMonotonicSeconds - (acceptedAtMonotonicSeconds ?? sentAtMonotonicSeconds)
        >= configuration.completionTimeoutSeconds {
        return .failedAwaitingCompletion
    }
    return .unchanged(status)
}
