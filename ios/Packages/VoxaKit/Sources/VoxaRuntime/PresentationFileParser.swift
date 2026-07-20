import Foundation
import VoxaCore

public struct PresentationParserLimits: Equatable, Sendable {
    public static let production = PresentationParserLimits(
        maxSourceFileBytes: 75 * 1_024 * 1_024,
        maxSlideCount: 100,
        maxArchiveEntryCount: 5_000,
        maxArchiveEntryBytes: 20 * 1_024 * 1_024,
        maxArchiveExpandedBytes: 200 * 1_024 * 1_024,
        maxSlideTextCharacters: 100_000,
        maxExtractedTextCharacters: 1_000_000
    )

    public let maxSourceFileBytes: UInt64
    public let maxSlideCount: Int
    public let maxArchiveEntryCount: Int
    public let maxArchiveEntryBytes: UInt64
    public let maxArchiveExpandedBytes: UInt64
    public let maxSlideTextCharacters: Int
    public let maxExtractedTextCharacters: Int

    public init(
        maxSourceFileBytes: UInt64,
        maxSlideCount: Int,
        maxArchiveEntryCount: Int,
        maxArchiveEntryBytes: UInt64,
        maxArchiveExpandedBytes: UInt64,
        maxSlideTextCharacters: Int,
        maxExtractedTextCharacters: Int
    ) {
        self.maxSourceFileBytes = maxSourceFileBytes
        self.maxSlideCount = maxSlideCount
        self.maxArchiveEntryCount = maxArchiveEntryCount
        self.maxArchiveEntryBytes = maxArchiveEntryBytes
        self.maxArchiveExpandedBytes = maxArchiveExpandedBytes
        self.maxSlideTextCharacters = maxSlideTextCharacters
        self.maxExtractedTextCharacters = maxExtractedTextCharacters
    }

    var isValid: Bool {
        maxSourceFileBytes > 0
            && maxSlideCount > 0
            && maxArchiveEntryCount > 0
            && maxArchiveEntryBytes > 0
            && maxArchiveEntryBytes <= UInt64(Int.max)
            && maxArchiveExpandedBytes >= maxArchiveEntryBytes
            && maxSlideTextCharacters > 0
            && maxExtractedTextCharacters >= maxSlideTextCharacters
    }
}

public enum PresentationParserError: Error, Equatable, Sendable {
    case invalidLimits
    case unsupportedFileExtension(String)
    case unreadableFile
    case sourceFileTooLarge(maximumBytes: UInt64)
    case malformedArchive
    case missingPresentation
    case missingRelationships
    case missingArchiveEntry(String)
    case missingSlideRelationship(String)
    case unsafeArchiveEntry(String)
    case unsafeRelationshipTarget(String)
    case noSlides
    case tooManySlides(maximum: Int)
    case tooManyArchiveEntries(maximum: Int)
    case archiveEntryTooLarge(path: String, maximumBytes: UInt64)
    case expandedArchiveTooLarge(maximumBytes: UInt64)
    case extractedTextTooLarge(maximumCharacters: Int)
    case malformedXML(String)
    case malformedPDF
    case encryptedPDF
}

extension PresentationParserError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "The presentation parser is not configured correctly."
        case let .unsupportedFileExtension(fileExtension):
            "Unsupported presentation format: .\(fileExtension). Choose a PDF or PowerPoint file."
        case .unreadableFile:
            "The presentation could not be read."
        case let .sourceFileTooLarge(maximumBytes):
            "The presentation is larger than the \(maximumBytes / 1_024 / 1_024) MB import limit."
        case .malformedArchive:
            "The PowerPoint file is damaged or is not a valid .pptx file."
        case .missingPresentation, .missingRelationships, .missingArchiveEntry, .missingSlideRelationship:
            "The PowerPoint file is missing required slide data."
        case .unsafeArchiveEntry, .unsafeRelationshipTarget:
            "The PowerPoint file contains an unsafe internal path."
        case .noSlides:
            "The presentation has no slides."
        case let .tooManySlides(maximum):
            "The presentation has more than \(maximum) slides."
        case let .tooManyArchiveEntries(maximum):
            "The PowerPoint file contains more than \(maximum) internal files."
        case let .archiveEntryTooLarge(_, maximumBytes):
            "One PowerPoint component is larger than the \(maximumBytes / 1_024 / 1_024) MB safety limit."
        case let .expandedArchiveTooLarge(maximumBytes):
            "The expanded PowerPoint file is larger than the \(maximumBytes / 1_024 / 1_024) MB safety limit."
        case let .extractedTextTooLarge(maximumCharacters):
            "The presentation contains more than \(maximumCharacters) text characters."
        case .malformedXML:
            "The PowerPoint file contains malformed slide data."
        case .malformedPDF:
            "The PDF is damaged or is not a valid PDF file."
        case .encryptedPDF:
            "Password-protected PDFs are not supported."
        }
    }
}

public struct PresentationFileParser: Sendable {
    private let limits: PresentationParserLimits

    public init(limits: PresentationParserLimits) {
        self.limits = limits
    }

    public func parse(url: URL) throws -> [DeckSlide] {
        switch url.pathExtension.lowercased() {
        case "pptx":
            try PowerPointParser(limits: limits).parse(url: url)
        case "pdf":
            try PDFPresentationParser(limits: limits).parse(url: url)
        default:
            throw PresentationParserError.unsupportedFileExtension(url.pathExtension.lowercased())
        }
    }
}

func validateSourceFile(url: URL, limits: PresentationParserLimits) throws {
    guard limits.isValid else { throw PresentationParserError.invalidLimits }
    guard url.isFileURL else { throw PresentationParserError.unreadableFile }
    let values: URLResourceValues
    do {
        values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    } catch {
        throw PresentationParserError.unreadableFile
    }
    guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize >= 0 else {
        throw PresentationParserError.unreadableFile
    }
    guard UInt64(fileSize) <= limits.maxSourceFileBytes else {
        throw PresentationParserError.sourceFileTooLarge(maximumBytes: limits.maxSourceFileBytes)
    }
}
