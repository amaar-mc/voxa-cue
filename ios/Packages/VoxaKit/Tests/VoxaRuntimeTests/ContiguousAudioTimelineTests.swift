import Testing
@testable import VoxaRuntime

@Test("Analyzer timestamps begin at zero and advance only by submitted frames")
func analyzerTimelineUsesSubmittedFrames() {
    var timeline = ContiguousAudioTimeline()

    #expect(timeline.consume(frameCount: 480, sampleRate: 48_000) == 0)
    #expect(timeline.consume(frameCount: 960, sampleRate: 48_000) == 0.01)
    #expect(timeline.consume(frameCount: 480, sampleRate: 48_000) == 0.03)
}
