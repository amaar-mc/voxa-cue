import Foundation
import NaturalLanguage

public struct SemanticMatcher: Sendable {
    public init() {}

    public func similarity(first: String, second: String) -> Double? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let firstVector = embedding.vector(for: first),
              let secondVector = embedding.vector(for: second),
              firstVector.count == secondVector.count,
              !firstVector.isEmpty else {
            return nil
        }
        let dot = zip(firstVector, secondVector).reduce(0.0) { $0 + $1.0 * $1.1 }
        let firstMagnitude = sqrt(firstVector.reduce(0.0) { $0 + $1 * $1 })
        let secondMagnitude = sqrt(secondVector.reduce(0.0) { $0 + $1 * $1 })
        guard firstMagnitude > 0, secondMagnitude > 0 else { return nil }
        return min(1, max(0, dot / (firstMagnitude * secondMagnitude)))
    }
}

