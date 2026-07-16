import Foundation
import Testing
import VoxaCore
@testable import VoxaCue

@Test("A late deck response is reconciled to the present target duration")
func lateDeckResponseUsesCurrentTargetDuration() {
    let original = PreparedDeckPlan(
        plan: DeckPlan(
            schemaVersion: 1,
            title: "Pitch",
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
                    label: "Solution",
                    targetCumulativeSeconds: 180,
                    semanticSummary: "Voxa Cue restores the coaching loop.",
                    anchorTerms: ["coaching", "haptics"]
                )
            ]
        ),
        source: .coachingAPI
    )

    let reconciled = reconciledPreparedDeck(
        original,
        requestedTargetDurationSeconds: 180,
        latestTargetDurationSeconds: 120
    )

    #expect(reconciled.plan.checkpoints.map(\.targetCumulativeSeconds) == [40, 120])
    #expect(reconciled.plan.checkpoints.map(\.semanticSummary) == original.plan.checkpoints.map(\.semanticSummary))
    #expect(reconciled.source == .coachingAPI)
}
