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

@Test("Rolling pace uses only words in the configured window")
func rollingPaceUsesWindow() {
    let words = [
        TimedWord(text: "old", endSeconds: 1),
        TimedWord(text: "one", endSeconds: 11),
        TimedWord(text: "two", endSeconds: 20)
    ]

    #expect(rollingWordsPerMinute(words: words, nowSeconds: 20, windowSeconds: 10) == 12)
}

@Test("Rolling pace uses elapsed session time before the window is full")
func rollingPaceUsesPartialOpeningWindow() {
    let words = (1...20).map { index in
        TimedWord(text: "word", endSeconds: Double(index) / 2)
    }

    #expect(rollingWordsPerMinute(words: words, nowSeconds: 10, windowSeconds: 20) == 120)
}

@Test("Pitch range is represented in semitones")
func pitchRangeUsesSemitones() {
    let result = pitchRangeSemitones(pitches: [100, 200])
    #expect(result != nil)
    #expect(abs((result ?? 0) - 12) < 0.001)
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
