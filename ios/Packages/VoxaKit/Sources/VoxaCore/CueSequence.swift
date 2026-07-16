public func nextCueSequence(after sequence: UInt16) -> UInt16 {
    sequence == UInt16.max ? 1 : sequence + 1
}

public func cueSequenceIsAhead(_ candidate: UInt16, of baseline: UInt16) -> Bool {
    let distance = candidate &- baseline
    return distance != 0 && distance < 0x8000
}
