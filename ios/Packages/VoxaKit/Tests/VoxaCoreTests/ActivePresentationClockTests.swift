import Testing
@testable import VoxaCore

@Test("Presentation clock excludes every paused interval")
func presentationClockExcludesPausedTime() {
    let started = ActivePresentationClock(startedAtReferenceSeconds: 100)
    let firstPause = started.pausing(atReferenceSeconds: 130)

    #expect(firstPause.elapsed(atReferenceSeconds: 150) == 30)

    let firstResume = firstPause.resuming(atReferenceSeconds: 150)
    #expect(firstResume.elapsed(atReferenceSeconds: 165) == 45)

    let secondPause = firstResume.pausing(atReferenceSeconds: 165)
    let secondResume = secondPause.resuming(atReferenceSeconds: 175)
    #expect(secondResume.elapsed(atReferenceSeconds: 185) == 55)
}

@Test("Repeated pause and resume requests are idempotent")
func presentationClockTransitionsAreIdempotent() {
    let started = ActivePresentationClock(startedAtReferenceSeconds: 20)
    let paused = started
        .pausing(atReferenceSeconds: 30)
        .pausing(atReferenceSeconds: 35)
    let resumed = paused
        .resuming(atReferenceSeconds: 40)
        .resuming(atReferenceSeconds: 45)

    #expect(resumed.elapsed(atReferenceSeconds: 50) == 20)
}
