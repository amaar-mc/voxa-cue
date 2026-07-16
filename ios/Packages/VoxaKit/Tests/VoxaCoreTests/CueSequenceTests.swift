import Testing
@testable import VoxaCore

@Test("Cue sequence advances without emitting the reserved zero value")
func cueSequenceWrapsPastZero() {
    #expect(nextCueSequence(after: 41) == 42)
    #expect(nextCueSequence(after: UInt16.max) == 1)
}

@Test("Cue sequence comparison follows firmware half-range ordering")
func cueSequenceComparisonMatchesFirmware() {
    #expect(cueSequenceIsAhead(101, of: 1))
    #expect(!cueSequenceIsAhead(101, of: 105))
    #expect(cueSequenceIsAhead(1, of: UInt16.max))
    #expect(!cueSequenceIsAhead(42, of: 42))
}
