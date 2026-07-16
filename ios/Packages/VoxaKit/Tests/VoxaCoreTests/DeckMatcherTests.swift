import Testing
@testable import VoxaCore

@Test("Checkpoint requires two anchors and a passing combined score")
func checkpointRequiresAnchors() {
    let checkpoint = DeckCheckpoint(
        id: "market",
        slideIndex: 2,
        label: "Market opportunity",
        targetCumulativeSeconds: 120,
        semanticSummary: "The public speaking coaching market is underserved.",
        anchorTerms: ["public speaking", "coaching", "market", "underserved"]
    )
    let result = matchDeckCheckpoint(
        DeckMatchInput(
            transcript: "The public speaking coaching market remains underserved.",
            checkpoint: checkpoint,
            semanticSimilarity: 0.9
        )
    )

    #expect(result.reached)
    #expect(result.matchedAnchorCount >= 2)
}

@Test("Anchor-only fallback remains conservative")
func anchorOnlyFallbackIsConservative() {
    let checkpoint = DeckCheckpoint(
        id: "solution",
        slideIndex: 1,
        label: "Solution",
        targetCumulativeSeconds: 60,
        semanticSummary: "A discreet wearable speech coach.",
        anchorTerms: ["wearable", "speech coach", "haptic", "discreet"]
    )
    let result = matchDeckCheckpoint(
        DeckMatchInput(
            transcript: "Our wearable is discreet.",
            checkpoint: checkpoint,
            semanticSimilarity: nil
        )
    )

    #expect(!result.reached)
}
