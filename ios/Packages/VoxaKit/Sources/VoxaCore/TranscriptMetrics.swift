import Foundation

public struct TranscriptAccumulator: Equatable, Sendable {
    public let segments: [FinalTranscriptSegment]

    public init(segments: [FinalTranscriptSegment]) {
        self.segments = segments.sorted { $0.startSeconds < $1.startSeconds }
    }

    public func inserting(_ segment: FinalTranscriptSegment) -> TranscriptAccumulator {
        let retained = segments.filter { existing in
            existing.endSeconds <= segment.startSeconds || existing.startSeconds >= segment.endSeconds
        }
        return TranscriptAccumulator(segments: retained + [segment])
    }

    public var transcript: String {
        segments.map(\.text).joined(separator: " ")
    }
}

public struct TranscriptAnalysis: Equatable, Sendable {
    public let words: [String]
    public let fillerCount: Int
    public let matchedFillers: [String]

    public init(words: [String], fillerCount: Int, matchedFillers: [String]) {
        self.words = words
        self.fillerCount = fillerCount
        self.matchedFillers = matchedFillers
    }
}

public func normalizedSpeechWords(_ text: String) -> [String] {
    text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
}

public func analyzeTranscript(_ text: String, fillers: [String]) -> TranscriptAnalysis {
    let words = normalizedSpeechWords(text)
    let normalizedText = " " + words.joined(separator: " ") + " "
    var matched: [String] = []

    for filler in fillers {
        let normalizedFiller = normalizedSpeechWords(filler).joined(separator: " ")
        guard !normalizedFiller.isEmpty else { continue }
        let needle = " " + normalizedFiller + " "
        var searchStart = normalizedText.startIndex
        while let range = normalizedText.range(of: needle, range: searchStart..<normalizedText.endIndex) {
            matched.append(normalizedFiller)
            searchStart = range.upperBound
        }
    }

    return TranscriptAnalysis(words: words, fillerCount: matched.count, matchedFillers: matched)
}

public func timedFillerOffsets(
    segments: [FinalTranscriptSegment],
    fillers: [String]
) -> [TimeInterval] {
    let phrases = fillers
        .map(normalizedSpeechWords)
        .filter { !$0.isEmpty }
        .sorted { first, second in
            if first.count == second.count {
                return first.joined(separator: " ") < second.joined(separator: " ")
            }
            return first.count > second.count
        }

    return segments.flatMap { segment in
        let words = normalizedSpeechWords(segment.text)
        guard !words.isEmpty else { return [TimeInterval]() }
        let duration = max(0, segment.endSeconds - segment.startSeconds)
        var occupiedWordIndexes = Set<Int>()
        var offsets: [TimeInterval] = []

        for phrase in phrases where phrase.count <= words.count {
            let lastStartIndex = words.count - phrase.count
            for startIndex in 0...lastStartIndex {
                let matchRange = startIndex..<(startIndex + phrase.count)
                guard !matchRange.contains(where: occupiedWordIndexes.contains) else { continue }
                let candidate = Array(words[matchRange])
                guard candidate == phrase else { continue }
                occupiedWordIndexes.formUnion(matchRange)
                let endFraction = Double(matchRange.upperBound) / Double(words.count)
                offsets.append(segment.startSeconds + duration * endFraction)
            }
        }
        return offsets
    }
    .sorted()
}

public func rollingWordsPerMinute(words: [TimedWord], nowSeconds: TimeInterval, windowSeconds: TimeInterval) -> Double {
    guard windowSeconds > 0 else { return 0 }
    let effectiveWindowSeconds = min(windowSeconds, max(0, nowSeconds))
    guard effectiveWindowSeconds > 0 else { return 0 }
    let lowerBound = max(0, nowSeconds - effectiveWindowSeconds)
    let count = words.filter { $0.endSeconds > lowerBound && $0.endSeconds <= nowSeconds }.count
    return Double(count) * 60 / effectiveWindowSeconds
}

public func computedTalkRatio(voicedSeconds: TimeInterval, elapsedSeconds: TimeInterval) -> Double {
    guard elapsedSeconds > 0 else { return 0 }
    return min(1, max(0, voicedSeconds / elapsedSeconds))
}

public func pitchRangeSemitones(pitches: [Double]) -> Double? {
    let voiced = pitches.filter { $0 > 0 }
    guard let minimum = voiced.min(), let maximum = voiced.max(), minimum > 0 else { return nil }
    return 12 * log2(maximum / minimum)
}

public func energyRangeDB(values: [Double]) -> Double? {
    guard let minimum = values.min(), let maximum = values.max() else { return nil }
    return maximum - minimum
}
