import Testing
@testable import VoxaCore

@Test("A cue fails when the band never acknowledges it")
func cueAcceptanceDeadlineExpires() {
    let evaluation = evaluateCueDeliveryDeadline(
        status: .pending,
        sentAtMonotonicSeconds: 100,
        acceptedAtMonotonicSeconds: nil,
        nowMonotonicSeconds: 102,
        configuration: CueDeliveryDeadlineConfiguration(
            acceptanceTimeoutSeconds: 2,
            completionTimeoutSeconds: 4
        )
    )

    #expect(evaluation == .failedAwaitingAcceptance)
}

@Test("An acknowledged cue fails when completion confirmation is lost")
func cueCompletionDeadlineExpires() {
    let evaluation = evaluateCueDeliveryDeadline(
        status: .accepted,
        sentAtMonotonicSeconds: 100,
        acceptedAtMonotonicSeconds: 101,
        nowMonotonicSeconds: 105,
        configuration: CueDeliveryDeadlineConfiguration(
            acceptanceTimeoutSeconds: 2,
            completionTimeoutSeconds: 4
        )
    )

    #expect(evaluation == .failedAwaitingCompletion)
}

@Test("Cue evidence remains live before its deadline")
func cueEvidenceRemainsLiveBeforeDeadline() {
    let evaluation = evaluateCueDeliveryDeadline(
        status: .pending,
        sentAtMonotonicSeconds: 100,
        acceptedAtMonotonicSeconds: nil,
        nowMonotonicSeconds: 101.99,
        configuration: CueDeliveryDeadlineConfiguration(
            acceptanceTimeoutSeconds: 2,
            completionTimeoutSeconds: 4
        )
    )

    #expect(evaluation == .unchanged(.pending))
}

@Test("Terminal cue delivery evidence never regresses")
func cueTerminalDeliveryRemainsTerminal() {
    let configuration = CueDeliveryDeadlineConfiguration(
        acceptanceTimeoutSeconds: 2,
        completionTimeoutSeconds: 4
    )

    for status in [CueDeliveryStatus.completed, .failed, .notConnected, .suppressed] {
        let evaluation = evaluateCueDeliveryDeadline(
            status: status,
            sentAtMonotonicSeconds: 100,
            acceptedAtMonotonicSeconds: nil,
            nowMonotonicSeconds: 1_000,
            configuration: configuration
        )
        #expect(evaluation == .unchanged(status))
    }
}
