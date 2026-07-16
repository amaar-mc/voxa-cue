import Foundation

public struct DeckMatchInput: Equatable, Sendable {
    public let transcript: String
    public let checkpoint: DeckCheckpoint
    public let semanticSimilarity: Double?

    public init(transcript: String, checkpoint: DeckCheckpoint, semanticSimilarity: Double?) {
        self.transcript = transcript
        self.checkpoint = checkpoint
        self.semanticSimilarity = semanticSimilarity
    }
}

public struct DeckMatchResult: Equatable, Sendable {
    public let combinedScore: Double
    public let anchorCoverage: Double
    public let matchedAnchorCount: Int
    public let reached: Bool

    public init(combinedScore: Double, anchorCoverage: Double, matchedAnchorCount: Int, reached: Bool) {
        self.combinedScore = combinedScore
        self.anchorCoverage = anchorCoverage
        self.matchedAnchorCount = matchedAnchorCount
        self.reached = reached
    }
}

public func matchDeckCheckpoint(_ input: DeckMatchInput) -> DeckMatchResult {
    let transcriptWords = Set(normalizedSpeechWords(input.transcript))
    let anchors = input.checkpoint.anchorTerms.map { normalizedSpeechWords($0) }.filter { !$0.isEmpty }
    let matched = anchors.filter { phraseWords in
        phraseWords.allSatisfy { transcriptWords.contains($0) }
    }.count
    let denominator = max(1, min(4, anchors.count))
    let coverage = min(1, Double(matched) / Double(denominator))

    if let semantic = input.semanticSimilarity {
        let combined = 0.65 * coverage + 0.35 * min(1, max(0, semantic))
        return DeckMatchResult(
            combinedScore: combined,
            anchorCoverage: coverage,
            matchedAnchorCount: matched,
            reached: combined >= 0.68 && matched >= 2
        )
    }

    return DeckMatchResult(
        combinedScore: coverage,
        anchorCoverage: coverage,
        matchedAnchorCount: matched,
        reached: coverage >= 0.75 && matched >= 2
    )
}
