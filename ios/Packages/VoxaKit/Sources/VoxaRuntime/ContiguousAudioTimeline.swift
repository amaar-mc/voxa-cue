import Foundation

struct ContiguousAudioTimeline {
    private var consumedFrameCount: Int64 = 0

    mutating func consume(frameCount: Int, sampleRate: Double) -> TimeInterval {
        guard frameCount > 0, sampleRate > 0 else { return TimeInterval(consumedFrameCount) / max(1, sampleRate) }
        let startSeconds = TimeInterval(consumedFrameCount) / sampleRate
        consumedFrameCount += Int64(frameCount)
        return startSeconds
    }
}
