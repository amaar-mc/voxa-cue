import Foundation

public struct DeckSlideDuration: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { slideIndex }
    public let slideIndex: Int
    public let durationSeconds: Int

    public init(slideIndex: Int, durationSeconds: Int) {
        self.slideIndex = slideIndex
        self.durationSeconds = durationSeconds
    }
}

public enum DeckTimingAllocation: Equatable, Sendable {
    case even(totalSeconds: Int)
    case perSlide(durations: [DeckSlideDuration], totalSeconds: Int)
}

public enum PresentationTimingError: Error, Equatable, Sendable {
    case noSlides
    case tooManySlides(maximum: Int)
    case invalidSlideIndex(Int)
    case duplicateSlideIndex(Int)
    case allocationCountMismatch
    case missingSlideIndex(Int)
    case unexpectedSlideIndex(Int)
    case invalidDuration(slideIndex: Int)
    case totalDurationTooShort(minimumSeconds: Int)
    case totalDurationMismatch(expectedSeconds: Int, actualSeconds: Int)
    case totalDurationOverflow
}

public func buildTimedDeckPlan(
    title: String,
    slides: [DeckSlide],
    allocation: DeckTimingAllocation
) throws -> DeckPlan {
    guard !slides.isEmpty else { throw PresentationTimingError.noSlides }
    guard slides.count <= 100 else { throw PresentationTimingError.tooManySlides(maximum: 100) }

    let orderedSlides = slides.sorted { first, second in first.index < second.index }
    var seenSlideIndexes = Set<Int>()
    for slide in orderedSlides {
        guard slide.index >= 0 else {
            throw PresentationTimingError.invalidSlideIndex(slide.index)
        }
        guard seenSlideIndexes.insert(slide.index).inserted else {
            throw PresentationTimingError.duplicateSlideIndex(slide.index)
        }
    }

    let durations = try resolvedDurations(slides: orderedSlides, allocation: allocation)
    var cumulativeSeconds = 0
    let checkpoints = zip(orderedSlides, durations).enumerated().map { position, pair in
        let (slide, durationSeconds) = pair
        cumulativeSeconds += durationSeconds
        return DeckCheckpoint(
            id: "slide-\(slide.index)",
            slideIndex: slide.index,
            label: boundedText(
                slide.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Slide \(position + 1)"
                    : slide.title,
                maximumCharacters: 120
            ),
            targetCumulativeSeconds: cumulativeSeconds,
            semanticSummary: "Timed slide checkpoint",
            anchorTerms: ["slide", "topic"]
        )
    }
    let normalizedTitle = boundedText(title, maximumCharacters: 120)
    return DeckPlan(
        schemaVersion: 1,
        title: normalizedTitle.isEmpty ? "Presentation" : normalizedTitle,
        checkpoints: checkpoints
    )
}

public func nextDueSlideTransition(
    plan: DeckPlan,
    elapsedSeconds: TimeInterval,
    deliveredCheckpointIDs: Set<String>
) -> DeckCheckpoint? {
    guard plan.checkpoints.count > 1 else { return nil }
    return plan.checkpoints.dropLast().first { checkpoint in
        elapsedSeconds >= TimeInterval(checkpoint.targetCumulativeSeconds)
            && !deliveredCheckpointIDs.contains(checkpoint.id)
    }
}

private func resolvedDurations(
    slides: [DeckSlide],
    allocation: DeckTimingAllocation
) throws -> [Int] {
    switch allocation {
    case let .even(totalSeconds):
        guard totalSeconds >= slides.count else {
            throw PresentationTimingError.totalDurationTooShort(minimumSeconds: slides.count)
        }
        let secondsPerSlide = totalSeconds / slides.count
        let remainder = totalSeconds % slides.count
        return slides.indices.map { index in
            secondsPerSlide + (index < remainder ? 1 : 0)
        }
    case let .perSlide(allocations, totalSeconds):
        guard totalSeconds >= slides.count else {
            throw PresentationTimingError.totalDurationTooShort(minimumSeconds: slides.count)
        }
        guard allocations.count == slides.count else {
            throw PresentationTimingError.allocationCountMismatch
        }
        var durationBySlideIndex: [Int: Int] = [:]
        var actualTotalSeconds = 0
        for timing in allocations {
            guard durationBySlideIndex[timing.slideIndex] == nil else {
                throw PresentationTimingError.duplicateSlideIndex(timing.slideIndex)
            }
            guard slides.contains(where: { $0.index == timing.slideIndex }) else {
                throw PresentationTimingError.unexpectedSlideIndex(timing.slideIndex)
            }
            guard timing.durationSeconds > 0 else {
                throw PresentationTimingError.invalidDuration(slideIndex: timing.slideIndex)
            }
            let (nextTotal, overflow) = actualTotalSeconds.addingReportingOverflow(timing.durationSeconds)
            guard !overflow else { throw PresentationTimingError.totalDurationOverflow }
            actualTotalSeconds = nextTotal
            durationBySlideIndex[timing.slideIndex] = timing.durationSeconds
        }
        guard actualTotalSeconds == totalSeconds else {
            throw PresentationTimingError.totalDurationMismatch(
                expectedSeconds: totalSeconds,
                actualSeconds: actualTotalSeconds
            )
        }
        return try slides.map { slide in
            guard let duration = durationBySlideIndex[slide.index] else {
                throw PresentationTimingError.missingSlideIndex(slide.index)
            }
            return duration
        }
    }
}

private func boundedText(_ text: String, maximumCharacters: Int) -> String {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > maximumCharacters else { return normalized }
    return String(normalized.prefix(maximumCharacters))
}
