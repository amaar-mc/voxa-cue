import Foundation
import Testing
@testable import VoxaCore

@Test("Final transcript revisions replace overlapping ranges")
func transcriptRevisionReplacesOverlap() {
    let first = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        startSeconds: 0,
        endSeconds: 2,
        text: "Hello um world"
    )
    let revised = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        startSeconds: 0,
        endSeconds: 2,
        text: "Hello world"
    )

    let result = TranscriptAccumulator(segments: [])
        .inserting(first)
        .inserting(revised)

    #expect(result.segments == [revised])
    #expect(result.transcript == "Hello world")
}

@Test("Filler matcher respects phrase boundaries")
func fillerMatcherUsesBoundaries() {
    let result = analyzeTranscript(
        "Um, you know this umbrella is actually useful. Uh.",
        fillers: ["um", "uh", "you know", "actually"]
    )

    #expect(result.fillerCount == 4)
    #expect(result.matchedFillers.sorted() == ["actually", "uh", "um", "you know"])
}

@Test("Contextual matcher counts repeated discourse like but not lexical like")
func contextualMatcherClassifiesLikeInContext() {
    let result = analyzePresentationTranscript(
        "Like, um, I don't know. Like, you know, like, what happens? Like, like, like. I like this application.",
        highConfidenceFillers: ["um", "uh", "you know"],
        contextualFillers: ["like"]
    )

    #expect(result.fillerCount == 8)
    #expect(result.matchedFillers.filter { $0 == "like" }.count == 6)
    #expect(result.matchedFillers.contains("um"))
    #expect(result.matchedFillers.contains("you know"))
}

@Test("Contextual matcher preserves ordinary uses of like")
func contextualMatcherRejectsLexicalLike() {
    let result = analyzePresentationTranscript(
        "I like this application. We like the interface. It feels like progress.",
        highConfidenceFillers: ["um", "uh", "you know"],
        contextualFillers: ["like"]
    )

    #expect(result.fillerCount == 0)
}

@Test("Contextual matcher counts parenthetical like after a pronoun")
func contextualMatcherCountsParentheticalLike() {
    let result = analyzePresentationTranscript(
        "I, like, don't really know.",
        highConfidenceFillers: ["um", "uh"],
        contextualFillers: ["like"]
    )

    #expect(result.matchedFillers == ["like"])
}

@Test("Contextual matcher distinguishes discourse phrases from literal statements")
func contextualMatcherClassifiesDiscoursePhrases() {
    let result = analyzePresentationTranscript(
        "You know the answer. I mean what I say. You know, the opening needs work. I mean, we can simplify it.",
        highConfidenceFillers: ["um", "uh"],
        contextualFillers: ["you know", "i mean"]
    )

    #expect(result.matchedFillers.sorted() == ["i mean", "you know"])
}

@Test("Contextual matcher excludes quotative and numeric approximation uses of like")
func contextualMatcherRejectsQuotativeAndNumericLike() {
    let result = analyzePresentationTranscript(
        "I was like, we should go. It costs like 20 dollars. Like, um, I lost my place.",
        highConfidenceFillers: ["um"],
        contextualFillers: ["like"]
    )

    #expect(result.matchedFillers.filter { $0 == "like" }.count == 1)
    #expect(result.matchedFillers.filter { $0 == "um" }.count == 1)
}

@Test("Filled-pause spelling variants are counted without partial-token matches")
func fillerMatcherCountsFilledPauseVariants() {
    let result = analyzePresentationTranscript(
        "Umm, uhh, uhm, this umbrella works.",
        highConfidenceFillers: ["um", "umm", "uh", "uhh", "uhm"],
        contextualFillers: []
    )

    #expect(result.matchedFillers.sorted() == ["uhh", "uhm", "umm"])
}

@Test("Speech word normalization preserves contractions")
func speechWordNormalizationPreservesContractions() {
    #expect(
        normalizedSpeechWords("Hello, don't split this—please.")
            == ["hello", "don't", "split", "this", "please"]
    )
}

@Test("Volatile transcript improves live pace without changing durable totals")
func volatileTranscriptPreviewsLivePace() {
    let finalized = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
        startSeconds: 0,
        endSeconds: 4,
        text: "one two three four"
    )
    let volatile = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
        startSeconds: 4,
        endSeconds: 6,
        text: "five six"
    )

    let preview = transcriptPaceSnapshot(
        finalizedSegments: [finalized],
        volatileSegment: volatile,
        nowSeconds: 6,
        windowSeconds: 8
    )
    let durable = transcriptPaceSnapshot(
        finalizedSegments: [finalized],
        volatileSegment: nil,
        nowSeconds: 6,
        windowSeconds: 8
    )

    #expect(abs(preview.rollingWPM - 60) < 0.001)
    #expect(preview.recognizedWordCount == 6)
    #expect(preview.finalizedWordCount == 4)
    #expect(preview.latestTranscriptEndSeconds == 6)
    #expect(abs(durable.rollingWPM - 40) < 0.001)
    #expect(durable.recognizedWordCount == 4)
}

@Test("Timestamped transcript pace falls as fast speech leaves the window")
func timestampedTranscriptPaceRespondsToSlowdown() {
    let fast = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
        startSeconds: 0,
        endSeconds: 8,
        text: Array(repeating: "fast", count: 24).joined(separator: " ")
    )
    let earlySlow = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
        startSeconds: 8,
        endSeconds: 10,
        text: "slow slow"
    )
    let laterSlow = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
        startSeconds: 8,
        endSeconds: 14,
        text: "slow slow slow slow slow slow"
    )

    let early = transcriptPaceSnapshot(
        finalizedSegments: [fast],
        volatileSegment: earlySlow,
        nowSeconds: 10,
        windowSeconds: 8
    )
    let later = transcriptPaceSnapshot(
        finalizedSegments: [fast],
        volatileSegment: laterSlow,
        nowSeconds: 14,
        windowSeconds: 8
    )

    #expect(abs(early.rollingWPM - 150) < 0.001)
    #expect(abs(later.rollingWPM - 90) < 0.001)
    #expect(later.rollingWPM < early.rollingWPM)
}

@Test("Stale volatile transcript ages out of live pace")
func staleVolatileTranscriptAgesOut() {
    let stale = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
        startSeconds: 0,
        endSeconds: 4,
        text: "one two three four"
    )

    let snapshot = transcriptPaceSnapshot(
        finalizedSegments: [],
        volatileSegment: stale,
        nowSeconds: 13,
        windowSeconds: 8
    )

    #expect(snapshot.rollingWPM == 0)
    #expect(snapshot.latestTranscriptEndSeconds == 4)
}

@Test("Pitch range is represented in semitones")
func pitchRangeUsesSemitones() {
    let result = pitchRangeSemitones(pitches: [100, 200])
    #expect(result != nil)
    #expect(abs((result ?? 0) - 12) < 0.001)
}

@Test("Energy span ignores isolated extrema")
func energySpanUsesRobustPercentiles() {
    let values = [-80.0, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, 0]

    let result = robustEnergyRangeDB(values: values)

    #expect(result != nil)
    #expect((result ?? 100) < 15)
}

@Test("Filler timestamps preserve their position inside long finalized segments")
func fillerOffsetsUseWordTiming() {
    let segment = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
        startSeconds: 0,
        endSeconds: 40,
        text: "um one two three four five six seven eight uh"
    )

    let offsets = timedFillerOffsets(segments: [segment], fillers: ["um", "uh"])

    #expect(offsets == [4, 40])
    #expect(offsets.filter { $0 > 20 }.count == 1)
}

@Test("Long filler phrases do not double count overlapping single words")
func fillerOffsetsPreferLongestPhrase() {
    let segment = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
        startSeconds: 0,
        endSeconds: 4,
        text: "you know this works"
    )

    let offsets = timedFillerOffsets(segments: [segment], fillers: ["know", "you know"])

    #expect(offsets == [2])
}

@Test("Contextual filler offsets use the same classification as summary metrics")
func contextualFillerOffsetsMatchSummaryClassification() {
    let segment = FinalTranscriptSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
        startSeconds: 0,
        endSeconds: 10,
        text: "Like, um, pause. Like, like. I like this app."
    )

    let offsets = timedPresentationFillerOffsets(
        segments: [segment],
        highConfidenceFillers: ["um"],
        contextualFillers: ["like"]
    )

    #expect(offsets.count == 4)
}

@Test("Timed filler matching recognizes a multiword phrase across transcript segments")
func timedFillerMatchingRecognizesCrossSegmentPhrase() {
    let segments = [
        FinalTranscriptSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            startSeconds: 0,
            endSeconds: 1,
            text: "you"
        ),
        FinalTranscriptSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            startSeconds: 1,
            endSeconds: 2,
            text: "know,"
        ),
    ]

    let offsets = timedPresentationFillerOffsets(
        segments: segments,
        highConfidenceFillers: ["um"],
        contextualFillers: ["you know"]
    )

    #expect(offsets == [2])
}

@Test("Timed filler matching counts repeated unpunctuated like across transcript segments")
func timedFillerMatchingCountsCrossSegmentContextualRepetition() {
    let segments = [
        FinalTranscriptSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            startSeconds: 0,
            endSeconds: 1,
            text: "like"
        ),
        FinalTranscriptSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
            startSeconds: 1,
            endSeconds: 2,
            text: "like"
        ),
        FinalTranscriptSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            startSeconds: 2,
            endSeconds: 3,
            text: "like"
        ),
    ]

    let offsets = timedPresentationFillerOffsets(
        segments: segments,
        highConfidenceFillers: ["um"],
        contextualFillers: ["like"]
    )

    #expect(offsets == [1, 2, 3])
}

@Test("Pause analytics include only internal speech gaps above the measurement floor")
func pauseAnalyticsUsesInternalSpeechGaps() {
    let intervals = [
        SpeechActivityInterval(isSpeech: false, startSeconds: 0, endSeconds: 2),
        SpeechActivityInterval(isSpeech: true, startSeconds: 2, endSeconds: 5),
        SpeechActivityInterval(isSpeech: false, startSeconds: 5, endSeconds: 5.3),
        SpeechActivityInterval(isSpeech: true, startSeconds: 5.3, endSeconds: 8),
        SpeechActivityInterval(isSpeech: false, startSeconds: 8, endSeconds: 9.25),
        SpeechActivityInterval(isSpeech: true, startSeconds: 9.25, endSeconds: 12),
        SpeechActivityInterval(isSpeech: false, startSeconds: 12, endSeconds: 16),
    ]

    let pauses = internalPauseDurations(intervals: intervals, minimumDurationSeconds: 0.5)

    #expect(pauses == [1.25])
}

@Test("Pause analytics merge adjacent non-speech detector ranges")
func pauseAnalyticsMergesAdjacentRanges() {
    let intervals = [
        SpeechActivityInterval(isSpeech: true, startSeconds: 0, endSeconds: 2),
        SpeechActivityInterval(isSpeech: false, startSeconds: 2, endSeconds: 2.4),
        SpeechActivityInterval(isSpeech: false, startSeconds: 2.4, endSeconds: 2.9),
        SpeechActivityInterval(isSpeech: true, startSeconds: 2.9, endSeconds: 4),
    ]

    let pauses = internalPauseDurations(intervals: intervals, minimumDurationSeconds: 0.5)

    #expect(pauses.count == 1)
    #expect(abs((pauses.first ?? 0) - 0.9) < 0.001)
}

@Test("Speech activity coverage counts overlapping detector ranges once")
func speechActivityCoverageMergesOverlaps() {
    let intervals = [
        SpeechActivityInterval(isSpeech: true, startSeconds: 0, endSeconds: 5),
        SpeechActivityInterval(isSpeech: false, startSeconds: 4, endSeconds: 8),
        SpeechActivityInterval(isSpeech: true, startSeconds: 8, endSeconds: 10),
        SpeechActivityInterval(isSpeech: true, startSeconds: 12, endSeconds: 11),
    ]

    #expect(speechActivityCoverageSeconds(intervals: intervals) == 10)
}

@Test("Pace variability ignores empty startup samples")
func paceVariabilityIgnoresEmptySamples() {
    let result = paceStandardDeviation(wpmSamples: [0, 130, 150, 170])

    #expect(result != nil)
    #expect(abs((result ?? 0) - 16.32993161855452) < 0.001)
    #expect(paceStandardDeviation(wpmSamples: [0, 0]) == nil)
}
