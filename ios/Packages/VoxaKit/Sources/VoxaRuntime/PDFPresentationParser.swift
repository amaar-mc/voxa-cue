import Foundation
import PDFKit
import VoxaCore

public struct PDFPresentationParser: Sendable {
    private let limits: PresentationParserLimits

    public init() {
        limits = .production
    }

    public init(limits: PresentationParserLimits) {
        self.limits = limits
    }

    public func parse(url: URL) throws -> [DeckSlide] {
        try validateSourceFile(url: url, limits: limits)
        guard let document = PDFDocument(url: url) else {
            throw PresentationParserError.malformedPDF
        }
        guard !document.isLocked else { throw PresentationParserError.encryptedPDF }
        guard document.pageCount > 0 else { throw PresentationParserError.noSlides }
        guard document.pageCount <= limits.maxSlideCount else {
            throw PresentationParserError.tooManySlides(maximum: limits.maxSlideCount)
        }

        var extractedCharacters = 0
        var slides: [DeckSlide] = []
        slides.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                throw PresentationParserError.malformedPDF
            }
            let text = page.string ?? ""
            guard text.count <= limits.maxSlideTextCharacters else {
                throw PresentationParserError.extractedTextTooLarge(
                    maximumCharacters: limits.maxSlideTextCharacters
                )
            }
            guard extractedCharacters <= limits.maxExtractedTextCharacters - text.count else {
                throw PresentationParserError.extractedTextTooLarge(
                    maximumCharacters: limits.maxExtractedTextCharacters
                )
            }
            extractedCharacters += text.count
            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            slides.append(
                DeckSlide(
                    id: UUID(),
                    index: index,
                    title: lines.first ?? "Slide \(index + 1)",
                    body: lines.dropFirst().joined(separator: " "),
                    notes: ""
                )
            )
        }
        return slides
    }
}
