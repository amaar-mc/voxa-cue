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

public func analyzePresentationTranscript(
    _ text: String,
    highConfidenceFillers: [String],
    contextualFillers: [String]
) -> TranscriptAnalysis {
    let tokens = indexedSpeechTokens(text)
    let matches = presentationFillerMatches(
        tokens: tokens,
        highConfidenceFillers: highConfidenceFillers,
        contextualFillers: contextualFillers
    )
    return TranscriptAnalysis(
        words: tokens.map(\.word),
        fillerCount: matches.count,
        matchedFillers: matches.map(\.phrase)
    )
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

public func timedPresentationFillerOffsets(
    segments: [FinalTranscriptSegment],
    highConfidenceFillers: [String],
    contextualFillers: [String]
) -> [TimeInterval] {
    segments.flatMap { segment in
        let tokens = indexedSpeechTokens(segment.text)
        guard !tokens.isEmpty else { return [TimeInterval]() }
        let matches = presentationFillerMatches(
            tokens: tokens,
            highConfidenceFillers: highConfidenceFillers,
            contextualFillers: contextualFillers
        )
        let duration = max(0, segment.endSeconds - segment.startSeconds)
        return matches.map { match in
            let endFraction = Double(match.endWordIndex + 1) / Double(tokens.count)
            return segment.startSeconds + duration * endFraction
        }
    }
    .sorted()
}

private struct IndexedSpeechToken {
    let word: String
    let separatorBefore: String
    let separatorAfter: String
}

private struct PresentationFillerMatch {
    let phrase: String
    let startWordIndex: Int
    let endWordIndex: Int
}

private func indexedSpeechTokens(_ text: String) -> [IndexedSpeechToken] {
    let nsText = text as NSString
    let pattern = "[\\p{L}\\p{N}']+"
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let matches = expression.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    return matches.enumerated().map { index, match in
        let previousEnd = index == 0 ? 0 : NSMaxRange(matches[index - 1].range)
        let nextStart = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
        let beforeRange = NSRange(location: previousEnd, length: match.range.location - previousEnd)
        let afterStart = NSMaxRange(match.range)
        let afterRange = NSRange(location: afterStart, length: nextStart - afterStart)
        return IndexedSpeechToken(
            word: nsText.substring(with: match.range).lowercased(),
            separatorBefore: nsText.substring(with: beforeRange),
            separatorAfter: nsText.substring(with: afterRange)
        )
    }
}

private func presentationFillerMatches(
    tokens: [IndexedSpeechToken],
    highConfidenceFillers: [String],
    contextualFillers: [String]
) -> [PresentationFillerMatch] {
    let highConfidencePhrases = normalizedPhrases(highConfidenceFillers)
    let contextualPhrases = normalizedPhrases(contextualFillers)
    var occupied = Set<Int>()
    var matches = exactPhraseMatches(tokens: tokens, phrases: highConfidencePhrases, occupied: &occupied)

    for phrase in contextualPhrases where phrase.count <= tokens.count {
        let occurrences = phraseOccurrences(tokens: tokens, phrase: phrase)
        for occurrence in occurrences {
            guard !occurrence.contains(where: occupied.contains) else { continue }
            guard contextualOccurrenceIsFiller(
                tokens: tokens,
                phrase: phrase,
                occurrence: occurrence,
                occurrenceCount: occurrences.count
            ) else { continue }
            occupied.formUnion(occurrence)
            matches.append(
                PresentationFillerMatch(
                    phrase: phrase.joined(separator: " "),
                    startWordIndex: occurrence.lowerBound,
                    endWordIndex: occurrence.upperBound - 1
                )
            )
        }
    }

    return matches.sorted { first, second in
        if first.startWordIndex == second.startWordIndex {
            return first.endWordIndex < second.endWordIndex
        }
        return first.startWordIndex < second.startWordIndex
    }
}

private func normalizedPhrases(_ fillers: [String]) -> [[String]] {
    fillers
        .map(normalizedSpeechWords)
        .filter { !$0.isEmpty }
        .sorted { first, second in
            if first.count == second.count {
                return first.joined(separator: " ") < second.joined(separator: " ")
            }
            return first.count > second.count
        }
}

private func exactPhraseMatches(
    tokens: [IndexedSpeechToken],
    phrases: [[String]],
    occupied: inout Set<Int>
) -> [PresentationFillerMatch] {
    var matches: [PresentationFillerMatch] = []
    for phrase in phrases where phrase.count <= tokens.count {
        for occurrence in phraseOccurrences(tokens: tokens, phrase: phrase) {
            guard !occurrence.contains(where: occupied.contains) else { continue }
            occupied.formUnion(occurrence)
            matches.append(
                PresentationFillerMatch(
                    phrase: phrase.joined(separator: " "),
                    startWordIndex: occurrence.lowerBound,
                    endWordIndex: occurrence.upperBound - 1
                )
            )
        }
    }
    return matches
}

private func phraseOccurrences(tokens: [IndexedSpeechToken], phrase: [String]) -> [Range<Int>] {
    guard !phrase.isEmpty, phrase.count <= tokens.count else { return [] }
    return (0...(tokens.count - phrase.count)).compactMap { startIndex in
        let range = startIndex..<(startIndex + phrase.count)
        return tokens[range].map(\.word) == phrase ? range : nil
    }
}

private func contextualOccurrenceIsFiller(
    tokens: [IndexedSpeechToken],
    phrase: [String],
    occurrence: Range<Int>,
    occurrenceCount: Int
) -> Bool {
    guard phrase == ["like"] else {
        let firstToken = tokens[occurrence.lowerBound]
        let lastToken = tokens[occurrence.upperBound - 1]
        return parentheticalPunctuationMarksExist(firstToken.separatorBefore)
            || parentheticalPunctuationMarksExist(lastToken.separatorAfter)
            || occurrenceCount >= 3
    }

    let index = occurrence.lowerBound
    let token = tokens[index]
    if isLexicalLike(tokens: tokens, index: index) {
        return false
    }
    if punctuationMarksExist(token.separatorBefore) || punctuationMarksExist(token.separatorAfter) {
        return true
    }
    return occurrenceCount >= 3
}

private func punctuationMarksExist(_ separator: String) -> Bool {
    separator.rangeOfCharacter(from: CharacterSet(charactersIn: ",.!?;:—–")) != nil
}

private func parentheticalPunctuationMarksExist(_ separator: String) -> Bool {
    separator.rangeOfCharacter(from: CharacterSet(charactersIn: ",;:—–")) != nil
}

private func isLexicalLike(tokens: [IndexedSpeechToken], index: Int) -> Bool {
    if index + 1 < tokens.count,
       tokens[index + 1].word.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains) {
        return true
    }
    guard index > 0 else { return false }
    let precedingWord = tokens[index - 1].word
    let comparisonVerbs: Set<String> = [
        "feel", "feels", "felt", "look", "looks", "looked", "seem", "seems", "seemed",
        "smell", "smells", "smelled", "sound", "sounds", "sounded", "taste", "tastes", "tasted",
    ]
    if comparisonVerbs.contains(precedingWord) { return true }
    let formsOfBe: Set<String> = ["am", "are", "be", "been", "being", "is", "was", "were"]
    if formsOfBe.contains(precedingWord) { return true }

    let subjects: Set<String> = ["i", "we", "you", "they", "he", "she", "it"]
    if subjects.contains(precedingWord) { return true }
    let adverbs: Set<String> = ["also", "really", "actually", "just", "still"]
    if index > 1, adverbs.contains(precedingWord), subjects.contains(tokens[index - 2].word) {
        return true
    }
    return false
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

public func speechActivityCoverageSeconds(intervals: [SpeechActivityInterval]) -> TimeInterval {
    let ordered = intervals
        .filter { interval in
            interval.startSeconds.isFinite
                && interval.endSeconds.isFinite
                && interval.endSeconds > interval.startSeconds
        }
        .sorted { first, second in
            if first.startSeconds == second.startSeconds {
                return first.endSeconds < second.endSeconds
            }
            return first.startSeconds < second.startSeconds
        }
    guard let first = ordered.first else { return 0 }

    var coverageSeconds = 0.0
    var currentStart = first.startSeconds
    var currentEnd = first.endSeconds
    for interval in ordered.dropFirst() {
        if interval.startSeconds <= currentEnd {
            currentEnd = max(currentEnd, interval.endSeconds)
        } else {
            coverageSeconds += currentEnd - currentStart
            currentStart = interval.startSeconds
            currentEnd = interval.endSeconds
        }
    }
    return coverageSeconds + currentEnd - currentStart
}

public func internalPauseDurations(
    intervals: [SpeechActivityInterval],
    minimumDurationSeconds: TimeInterval
) -> [TimeInterval] {
    guard minimumDurationSeconds.isFinite, minimumDurationSeconds >= 0 else { return [] }
    let ordered = intervals
        .filter { interval in
            interval.startSeconds.isFinite
                && interval.endSeconds.isFinite
                && interval.endSeconds > interval.startSeconds
        }
        .sorted { first, second in
            if first.startSeconds == second.startSeconds {
                return first.endSeconds < second.endSeconds
            }
            return first.startSeconds < second.startSeconds
        }
    guard ordered.contains(where: \.isSpeech) else { return [] }

    var merged: [SpeechActivityInterval] = []
    for interval in ordered {
        if let last = merged.last,
           last.isSpeech == interval.isSpeech,
           interval.startSeconds <= last.endSeconds + 0.05 {
            merged[merged.count - 1] = SpeechActivityInterval(
                isSpeech: last.isSpeech,
                startSeconds: last.startSeconds,
                endSeconds: max(last.endSeconds, interval.endSeconds)
            )
        } else {
            merged.append(interval)
        }
    }

    return merged.enumerated().compactMap { index, interval in
        guard !interval.isSpeech,
              interval.endSeconds - interval.startSeconds >= minimumDurationSeconds,
              merged[..<index].contains(where: \.isSpeech),
              merged[(index + 1)...].contains(where: \.isSpeech) else {
            return nil
        }
        return interval.endSeconds - interval.startSeconds
    }
}

public func paceStandardDeviation(wpmSamples: [Double]) -> Double? {
    let valid = wpmSamples.filter { $0.isFinite && $0 > 0 }
    guard !valid.isEmpty else { return nil }
    let mean = valid.reduce(0, +) / Double(valid.count)
    let variance = valid.reduce(0) { partial, value in
        partial + (value - mean) * (value - mean)
    } / Double(valid.count)
    return sqrt(max(0, variance))
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

public func robustEnergyRangeDB(values: [Double]) -> Double? {
    let valid = values.filter(\.isFinite).sorted()
    guard valid.count >= 5 else { return nil }
    return interpolatedPercentile(valid, fraction: 0.9)
        - interpolatedPercentile(valid, fraction: 0.1)
}

private func interpolatedPercentile(_ sortedValues: [Double], fraction: Double) -> Double {
    guard !sortedValues.isEmpty else { return 0 }
    let boundedFraction = min(1, max(0, fraction))
    let position = boundedFraction * Double(sortedValues.count - 1)
    let lowerIndex = Int(floor(position))
    let upperIndex = Int(ceil(position))
    guard lowerIndex != upperIndex else { return sortedValues[lowerIndex] }
    let upperWeight = position - Double(lowerIndex)
    return sortedValues[lowerIndex] * (1 - upperWeight)
        + sortedValues[upperIndex] * upperWeight
}
