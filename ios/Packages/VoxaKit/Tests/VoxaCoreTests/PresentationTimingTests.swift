import Foundation
import Testing
@testable import VoxaCore

@Test("Even timing preserves every slide and divides the remainder deterministically")
func evenPresentationTiming() throws {
    let slides = makeSlides(count: 3)

    let plan = try buildTimedDeckPlan(
        title: "Demo pitch",
        slides: slides,
        allocation: .even(totalSeconds: 100)
    )

    #expect(plan.checkpoints.map(\.slideIndex) == [0, 1, 2])
    #expect(plan.checkpoints.map(\.targetCumulativeSeconds) == [34, 67, 100])
    #expect(plan.checkpoints.last?.targetCumulativeSeconds == 100)
    #expect(plan.checkpoints.allSatisfy { $0.semanticSummary == "Timed slide checkpoint" })
    #expect(plan.checkpoints.allSatisfy { $0.anchorTerms == ["slide", "topic"] })
}

@Test("Timed plans remain valid without retaining presentation content")
func timedPlanContractSafety() throws {
    let plan = try buildTimedDeckPlan(
        title: "   ",
        slides: [
            DeckSlide(
                id: UUID(),
                index: 0,
                title: "   ",
                body: "Private launch details",
                notes: "Confidential speaker notes"
            ),
        ],
        allocation: .even(totalSeconds: 60)
    )

    #expect(plan.title == "Presentation")
    #expect(plan.checkpoints[0].label == "Slide 1")
    #expect(plan.checkpoints[0].semanticSummary == "Timed slide checkpoint")
    #expect(!plan.checkpoints[0].semanticSummary.contains("Private"))
    #expect(!plan.checkpoints[0].semanticSummary.contains("Confidential"))
}

@Test("Advanced timing uses one explicit positive duration per slide")
func customPresentationTiming() throws {
    let slides = makeSlides(count: 3)
    let allocations = [
        DeckSlideDuration(slideIndex: 0, durationSeconds: 20),
        DeckSlideDuration(slideIndex: 1, durationSeconds: 45),
        DeckSlideDuration(slideIndex: 2, durationSeconds: 25),
    ]

    let plan = try buildTimedDeckPlan(
        title: "Custom pitch",
        slides: slides,
        allocation: .perSlide(durations: allocations, totalSeconds: 90)
    )

    #expect(plan.checkpoints.map(\.targetCumulativeSeconds) == [20, 65, 90])
}

@Test("Advanced timing rejects missing, duplicate, and non-positive allocations")
func invalidCustomPresentationTiming() {
    let slides = makeSlides(count: 2)

    #expect(throws: PresentationTimingError.allocationCountMismatch) {
        try buildTimedDeckPlan(
            title: "Missing",
            slides: slides,
            allocation: .perSlide(
                durations: [DeckSlideDuration(slideIndex: 0, durationSeconds: 30)],
                totalSeconds: 60
            )
        )
    }
    #expect(throws: PresentationTimingError.duplicateSlideIndex(0)) {
        try buildTimedDeckPlan(
            title: "Duplicate",
            slides: slides,
            allocation: .perSlide(
                durations: [
                    DeckSlideDuration(slideIndex: 0, durationSeconds: 30),
                    DeckSlideDuration(slideIndex: 0, durationSeconds: 30),
                ],
                totalSeconds: 60
            )
        )
    }
    #expect(throws: PresentationTimingError.invalidDuration(slideIndex: 1)) {
        try buildTimedDeckPlan(
            title: "Invalid",
            slides: slides,
            allocation: .perSlide(
                durations: [
                    DeckSlideDuration(slideIndex: 0, durationSeconds: 60),
                    DeckSlideDuration(slideIndex: 1, durationSeconds: 0),
                ],
                totalSeconds: 60
            )
        )
    }
}

@Test("Advanced timing validates its exact total without integer overflow")
func customPresentationTimingValidatesTotal() {
    let slides = makeSlides(count: 2)

    #expect(throws: PresentationTimingError.totalDurationMismatch(expectedSeconds: 90, actualSeconds: 40)) {
        try buildTimedDeckPlan(
            title: "Mismatch",
            slides: slides,
            allocation: .perSlide(
                durations: [
                    DeckSlideDuration(slideIndex: 0, durationSeconds: 20),
                    DeckSlideDuration(slideIndex: 1, durationSeconds: 20),
                ],
                totalSeconds: 90
            )
        )
    }
    #expect(throws: PresentationTimingError.totalDurationOverflow) {
        try buildTimedDeckPlan(
            title: "Overflow",
            slides: slides,
            allocation: .perSlide(
                durations: [
                    DeckSlideDuration(slideIndex: 0, durationSeconds: Int.max),
                    DeckSlideDuration(slideIndex: 1, durationSeconds: 1),
                ],
                totalSeconds: Int.max
            )
        )
    }
}

@Test("The final slide is never returned as a transition")
func dueSlideTransitionsExcludeFinalSlide() throws {
    let plan = try buildTimedDeckPlan(
        title: "Three slides",
        slides: makeSlides(count: 3),
        allocation: .even(totalSeconds: 90)
    )

    #expect(nextDueSlideTransition(plan: plan, elapsedSeconds: 29.9, deliveredCheckpointIDs: []) == nil)
    #expect(nextDueSlideTransition(plan: plan, elapsedSeconds: 30, deliveredCheckpointIDs: [])?.slideIndex == 0)
    #expect(
        nextDueSlideTransition(
            plan: plan,
            elapsedSeconds: 60,
            deliveredCheckpointIDs: ["slide-0"]
        )?.slideIndex == 1
    )
    #expect(
        nextDueSlideTransition(
            plan: plan,
            elapsedSeconds: 90,
            deliveredCheckpointIDs: ["slide-0", "slide-1"]
        ) == nil
    )
}

@Test("Timing rejects empty, duplicate, oversized, and impossibly short decks")
func invalidPresentationDecks() {
    #expect(throws: PresentationTimingError.noSlides) {
        try buildTimedDeckPlan(title: "Empty", slides: [], allocation: .even(totalSeconds: 60))
    }
    #expect(throws: PresentationTimingError.duplicateSlideIndex(0)) {
        try buildTimedDeckPlan(
            title: "Duplicate",
            slides: [makeSlides(count: 1)[0], makeSlides(count: 1)[0]],
            allocation: .even(totalSeconds: 60)
        )
    }
    #expect(throws: PresentationTimingError.tooManySlides(maximum: 100)) {
        try buildTimedDeckPlan(
            title: "Too many",
            slides: makeSlides(count: 101),
            allocation: .even(totalSeconds: 600)
        )
    }
    #expect(throws: PresentationTimingError.totalDurationTooShort(minimumSeconds: 3)) {
        try buildTimedDeckPlan(
            title: "Too short",
            slides: makeSlides(count: 3),
            allocation: .even(totalSeconds: 2)
        )
    }
    #expect(throws: PresentationTimingError.invalidSlideIndex(-1)) {
        try buildTimedDeckPlan(
            title: "Invalid index",
            slides: [
                DeckSlide(
                    id: UUID(),
                    index: -1,
                    title: "Slide",
                    body: "Body",
                    notes: "Notes"
                ),
            ],
            allocation: .even(totalSeconds: 60)
        )
    }
}

private func makeSlides(count: Int) -> [DeckSlide] {
    (0..<count).map { index in
        DeckSlide(
            id: UUID(),
            index: index,
            title: "Slide \(index + 1)",
            body: "Body for slide \(index + 1)",
            notes: "Notes for slide \(index + 1)"
        )
    }
}
