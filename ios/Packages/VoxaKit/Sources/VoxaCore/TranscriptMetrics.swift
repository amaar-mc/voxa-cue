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

public struct FillerFrequency: Codable, Equatable, Identifiable, Sendable {
    public let phrase: String
    public let count: Int

    public var id: String { phrase }

    public init(phrase: String, count: Int) {
        self.phrase = phrase
        self.count = count
    }
}

public func normalizedSpeechWords(_ text: String) -> [String] {
    text.lowercased()
        .replacingOccurrences(of: "’", with: "'")
        .split { character in
            !character.isLetter && !character.isNumber && character != "'"
        }
        .map(String.init)
        .filter { token in
            token.contains { $0.isLetter || $0.isNumber }
        }
}

public struct TranscriptPaceSnapshot: Equatable, Sendable {
    public let rollingWPM: Double
    public let finalizedWordCount: Int
    public let recognizedWordCount: Int
    public let latestTranscriptEndSeconds: TimeInterval?

    public init(
        rollingWPM: Double,
        finalizedWordCount: Int,
        recognizedWordCount: Int,
        latestTranscriptEndSeconds: TimeInterval?
    ) {
        self.rollingWPM = rollingWPM
        self.finalizedWordCount = finalizedWordCount
        self.recognizedWordCount = recognizedWordCount
        self.latestTranscriptEndSeconds = latestTranscriptEndSeconds
    }
}

public func transcriptPaceSnapshot(
    finalizedSegments: [FinalTranscriptSegment],
    volatileSegment: FinalTranscriptSegment?,
    nowSeconds: TimeInterval,
    windowSeconds: TimeInterval
) -> TranscriptPaceSnapshot {
    let finalizedSamples = finalizedSegments.compactMap(transcriptPaceSample)
    let finalizedWordCount = finalizedSamples.reduce(0) { $0 + $1.wordCount }
    var liveSamples = finalizedSamples

    if let volatileSample = volatileSegment.flatMap(transcriptPaceSample) {
        liveSamples.removeAll { finalizedSample in
            finalizedSample.startSeconds < volatileSample.endSeconds
                && volatileSample.startSeconds < finalizedSample.endSeconds
        }
        liveSamples.append(volatileSample)
    }

    let recognizedWordCount = liveSamples.reduce(0) { $0 + $1.wordCount }
    let latestTranscriptEndSeconds = liveSamples.map(\.endSeconds).max()
    guard nowSeconds.isFinite, windowSeconds.isFinite, nowSeconds > 0, windowSeconds > 0 else {
        return TranscriptPaceSnapshot(
            rollingWPM: 0,
            finalizedWordCount: finalizedWordCount,
            recognizedWordCount: recognizedWordCount,
            latestTranscriptEndSeconds: latestTranscriptEndSeconds
        )
    }

    let windowStart = max(0, nowSeconds - windowSeconds)
    let estimatedWords = liveSamples.reduce(0.0) { partial, sample in
        partial + transcriptWordContribution(
            sample: sample,
            windowStart: windowStart,
            windowEnd: nowSeconds
        )
    }
    guard estimatedWords > 0, let firstSpeechSeconds = liveSamples.map(\.startSeconds).min() else {
        return TranscriptPaceSnapshot(
            rollingWPM: 0,
            finalizedWordCount: finalizedWordCount,
            recognizedWordCount: recognizedWordCount,
            latestTranscriptEndSeconds: latestTranscriptEndSeconds
        )
    }

    let measurementStart = max(windowStart, firstSpeechSeconds)
    let measurementDuration = max(1, nowSeconds - measurementStart)
    return TranscriptPaceSnapshot(
        rollingWPM: estimatedWords * 60 / measurementDuration,
        finalizedWordCount: finalizedWordCount,
        recognizedWordCount: recognizedWordCount,
        latestTranscriptEndSeconds: latestTranscriptEndSeconds
    )
}

private struct TranscriptPaceSample {
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let wordCount: Int
}

private func transcriptPaceSample(segment: FinalTranscriptSegment) -> TranscriptPaceSample? {
    guard segment.startSeconds.isFinite,
          segment.endSeconds.isFinite,
          segment.startSeconds >= 0,
          segment.endSeconds >= segment.startSeconds else {
        return nil
    }
    let wordCount = normalizedSpeechWords(segment.text).count
    guard wordCount > 0 else { return nil }
    return TranscriptPaceSample(
        startSeconds: segment.startSeconds,
        endSeconds: segment.endSeconds,
        wordCount: wordCount
    )
}

private func transcriptWordContribution(
    sample: TranscriptPaceSample,
    windowStart: TimeInterval,
    windowEnd: TimeInterval
) -> Double {
    let sampleDuration = sample.endSeconds - sample.startSeconds
    guard sampleDuration > 0 else {
        return sample.endSeconds >= windowStart && sample.endSeconds <= windowEnd
            ? Double(sample.wordCount)
            : 0
    }
    let overlapStart = max(sample.startSeconds, windowStart)
    let overlapEnd = min(sample.endSeconds, windowEnd)
    let overlap = max(0, overlapEnd - overlapStart)
    return Double(sample.wordCount) * overlap / sampleDuration
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

public func presentationFillerBreakdown(
    _ text: String,
    highConfidenceFillers: [String],
    contextualFillers: [String]
) -> [FillerFrequency] {
    let analysis = analyzePresentationTranscript(
        text,
        highConfidenceFillers: highConfidenceFillers,
        contextualFillers: contextualFillers
    )
    let counts = analysis.matchedFillers.reduce(into: [String: Int]()) { partial, phrase in
        partial[phrase, default: 0] += 1
    }
    return counts
        .map { FillerFrequency(phrase: $0.key, count: $0.value) }
        .sorted { first, second in
            if first.count == second.count {
                return first.phrase < second.phrase
            }
            return first.count > second.count
        }
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
    let timedTokens = chronologicalTimedSpeechTokens(segments: segments)
    guard !timedTokens.isEmpty else { return [] }
    let matches = presentationFillerMatches(
        tokens: timedTokens.map(\.token),
        highConfidenceFillers: highConfidenceFillers,
        contextualFillers: contextualFillers
    )
    return matches.map { match in
        timedTokens[match.endWordIndex].endSeconds
    }
    .sorted()
}

private struct TimedIndexedSpeechToken {
    var token: IndexedSpeechToken
    let endSeconds: TimeInterval
}

private func chronologicalTimedSpeechTokens(
    segments: [FinalTranscriptSegment]
) -> [TimedIndexedSpeechToken] {
    var result: [TimedIndexedSpeechToken] = []
    for segment in segments.sorted(by: chronologicalSegmentOrder) {
        let tokens = indexedSpeechTokens(segment.text)
        guard !tokens.isEmpty else { continue }
        let duration = max(0, segment.endSeconds - segment.startSeconds)
        var segmentTokens = tokens.enumerated().map { index, token in
            let endFraction = Double(index + 1) / Double(tokens.count)
            return TimedIndexedSpeechToken(
                token: token,
                endSeconds: segment.startSeconds + duration * endFraction
            )
        }

        if let previousIndex = result.indices.last,
           let firstSegmentIndex = segmentTokens.indices.first {
            let previous = result[previousIndex]
            let first = segmentTokens[firstSegmentIndex]
            let boundarySeparator = previous.token.separatorAfter + first.token.separatorBefore
            result[previousIndex].token = IndexedSpeechToken(
                word: previous.token.word,
                separatorBefore: previous.token.separatorBefore,
                separatorAfter: boundarySeparator
            )
            segmentTokens[firstSegmentIndex].token = IndexedSpeechToken(
                word: first.token.word,
                separatorBefore: boundarySeparator,
                separatorAfter: first.token.separatorAfter
            )
        }
        result.append(contentsOf: segmentTokens)
    }
    return result
}

private func chronologicalSegmentOrder(
    first: FinalTranscriptSegment,
    second: FinalTranscriptSegment
) -> Bool {
    if first.startSeconds == second.startSeconds {
        return first.endSeconds < second.endSeconds
    }
    return first.startSeconds < second.startSeconds
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
    if punctuationMarksExist(token.separatorBefore) {
        return true
    }
    if isLexicalLike(tokens: tokens, index: index) {
        return false
    }
    if punctuationMarksExist(token.separatorAfter) {
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
