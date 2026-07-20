import Foundation
import VoxaCore
import ZIPFoundation

public typealias PowerPointParserError = PresentationParserError

public struct PowerPointParser: Sendable {
    private let limits: PresentationParserLimits

    public init() {
        limits = .production
    }

    public init(limits: PresentationParserLimits) {
        self.limits = limits
    }

    public func parse(url: URL) throws -> [DeckSlide] {
        try validateSourceFile(url: url, limits: limits)
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw PresentationParserError.malformedArchive
        }
        try validate(archive: archive)

        let presentationData = try data(
            in: archive,
            path: "ppt/presentation.xml",
            missingError: .missingPresentation
        )
        let relationshipData = try data(
            in: archive,
            path: "ppt/_rels/presentation.xml.rels",
            missingError: .missingRelationships
        )
        let slideRelationshipIDs = try presentationOrder(data: presentationData)
        guard !slideRelationshipIDs.isEmpty else { throw PresentationParserError.noSlides }
        guard slideRelationshipIDs.count <= limits.maxSlideCount else {
            throw PresentationParserError.tooManySlides(maximum: limits.maxSlideCount)
        }
        let presentationRelationships = try relationships(data: relationshipData)

        var slidePaths: [String] = []
        slidePaths.reserveCapacity(slideRelationshipIDs.count)
        for relationshipID in slideRelationshipIDs {
            guard let relationship = presentationRelationships[relationshipID],
                  relationship.type.hasSuffix("/slide")
            else {
                throw PresentationParserError.missingSlideRelationship(relationshipID)
            }
            guard !relationship.isExternal else {
                throw PresentationParserError.unsafeRelationshipTarget(relationship.target)
            }
            let path = try normalizedArchivePath(
                basePath: "ppt/presentation.xml",
                target: relationship.target,
                requiredPrefix: "ppt/slides/"
            )
            guard !slidePaths.contains(path) else {
                throw PresentationParserError.malformedXML("Duplicate slide relationship")
            }
            slidePaths.append(path)
        }

        var totalTextCharacters = 0
        var slides: [DeckSlide] = []
        slides.reserveCapacity(slidePaths.count)
        for (offset, slidePath) in slidePaths.enumerated() {
            let slideData = try data(
                in: archive,
                path: slidePath,
                missingError: .missingArchiveEntry(slidePath)
            )
            let availableTotal = limits.maxExtractedTextCharacters - totalTextCharacters
            let slideBudget = min(limits.maxSlideTextCharacters, availableTotal)
            let slideRuns = try textRuns(data: slideData, maximumCharacters: slideBudget)
            var slideTextCharacters = slideRuns.characterCount
            totalTextCharacters += slideRuns.characterCount

            let notesBudget = min(
                limits.maxSlideTextCharacters - slideTextCharacters,
                limits.maxExtractedTextCharacters - totalTextCharacters
            )
            let notes = try notesText(
                in: archive,
                slidePath: slidePath,
                slideStrings: Set(slideRuns.strings),
                maximumCharacters: notesBudget
            )
            slideTextCharacters += notes.characterCount
            totalTextCharacters += notes.characterCount

            slides.append(
                DeckSlide(
                    id: UUID(),
                    index: offset,
                    title: slideRuns.strings.first ?? "Slide \(offset + 1)",
                    body: slideRuns.strings.dropFirst().joined(separator: " "),
                    notes: notes.text
                )
            )
        }
        return slides
    }

    private func validate(archive: Archive) throws {
        var entryCount = 0
        var expandedBytes: UInt64 = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= limits.maxArchiveEntryCount else {
                throw PresentationParserError.tooManyArchiveEntries(maximum: limits.maxArchiveEntryCount)
            }
            guard isSafeArchivePath(entry.path), entry.type != .symlink else {
                throw PresentationParserError.unsafeArchiveEntry(entry.path)
            }
            guard entry.uncompressedSize <= limits.maxArchiveEntryBytes else {
                throw PresentationParserError.archiveEntryTooLarge(
                    path: entry.path,
                    maximumBytes: limits.maxArchiveEntryBytes
                )
            }
            guard expandedBytes <= limits.maxArchiveExpandedBytes - entry.uncompressedSize else {
                throw PresentationParserError.expandedArchiveTooLarge(
                    maximumBytes: limits.maxArchiveExpandedBytes
                )
            }
            expandedBytes += entry.uncompressedSize
        }
    }

    private func notesText(
        in archive: Archive,
        slidePath: String,
        slideStrings: Set<String>,
        maximumCharacters: Int
    ) throws -> (text: String, characterCount: Int) {
        let slideDirectory = (slidePath as NSString).deletingLastPathComponent
        let relationshipsDirectory = (slideDirectory as NSString).appendingPathComponent("_rels")
        let relationshipsPath = (relationshipsDirectory as NSString)
            .appendingPathComponent((slidePath as NSString).lastPathComponent + ".rels")
        guard archive[relationshipsPath] != nil else { return ("", 0) }
        let relationData = try data(
            in: archive,
            path: relationshipsPath,
            missingError: .missingArchiveEntry(relationshipsPath)
        )
        let relationMap = try relationships(data: relationData)
        guard let notesRelation = relationMap.values.first(where: { $0.type.hasSuffix("/notesSlide") }) else {
            return ("", 0)
        }
        guard !notesRelation.isExternal else {
            throw PresentationParserError.unsafeRelationshipTarget(notesRelation.target)
        }
        let notesPath = try normalizedArchivePath(
            basePath: slidePath,
            target: notesRelation.target,
            requiredPrefix: "ppt/notesSlides/"
        )
        guard archive[notesPath] != nil else {
            throw PresentationParserError.missingArchiveEntry(notesPath)
        }
        let notesRuns = try textRuns(
            data: data(in: archive, path: notesPath, missingError: .missingArchiveEntry(notesPath)),
            maximumCharacters: maximumCharacters
        )
        let filtered = notesRuns.strings.filter { !slideStrings.contains($0) }
        return (filtered.joined(separator: " "), filtered.reduce(0) { $0 + $1.count })
    }

    private func data(
        in archive: Archive,
        path: String,
        missingError: PresentationParserError
    ) throws -> Data {
        guard let entry = archive[path], entry.type == .file else { throw missingError }
        var result = Data()
        result.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry, consumer: { chunk in
                result.append(chunk)
            })
        } catch {
            throw PresentationParserError.malformedArchive
        }
        guard UInt64(result.count) == entry.uncompressedSize else {
            throw PresentationParserError.malformedArchive
        }
        return result
    }

    private func presentationOrder(data: Data) throws -> [String] {
        let delegate = PresentationOrderDelegate()
        try parse(data: data, delegate: delegate)
        return delegate.relationshipIDs
    }

    private func relationships(data: Data) throws -> [String: OfficeRelationship] {
        let delegate = RelationshipsDelegate()
        try parse(data: data, delegate: delegate)
        var result: [String: OfficeRelationship] = [:]
        for relationship in delegate.relationships {
            guard result[relationship.id] == nil else {
                throw PresentationParserError.malformedXML("Duplicate relationship id")
            }
            result[relationship.id] = relationship
        }
        return result
    }

    private func textRuns(data: Data, maximumCharacters: Int) throws -> TextRunResult {
        guard maximumCharacters >= 0 else {
            throw PresentationParserError.extractedTextTooLarge(maximumCharacters: 0)
        }
        let delegate = TextRunsDelegate(maximumCharacters: maximumCharacters)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let parsed = parser.parse()
        if delegate.exceededLimit {
            throw PresentationParserError.extractedTextTooLarge(maximumCharacters: maximumCharacters)
        }
        guard parsed else {
            throw PresentationParserError.malformedXML(
                parser.parserError?.localizedDescription ?? "Unknown XML error"
            )
        }
        let strings = delegate.strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return TextRunResult(
            strings: strings,
            characterCount: strings.reduce(0) { $0 + $1.count }
        )
    }

    private func parse(data: Data, delegate: XMLParserDelegate) throws {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            throw PresentationParserError.malformedXML(
                parser.parserError?.localizedDescription ?? "Unknown XML error"
            )
        }
    }

    private func normalizedArchivePath(
        basePath: String,
        target: String,
        requiredPrefix: String
    ) throws -> String {
        guard !target.isEmpty,
              !target.hasPrefix("/"),
              !target.contains("\\"),
              !target.contains(":")
        else {
            throw PresentationParserError.unsafeRelationshipTarget(target)
        }
        let decodedTarget = target.removingPercentEncoding ?? target
        guard !decodedTarget.hasPrefix("/"),
              !decodedTarget.contains("\\"),
              !decodedTarget.contains(":")
        else {
            throw PresentationParserError.unsafeRelationshipTarget(target)
        }
        var components = basePath.split(separator: "/").dropLast().map(String.init)
        for component in decodedTarget.split(separator: "/", omittingEmptySubsequences: false) {
            switch component {
            case "", ".":
                continue
            case "..":
                guard !components.isEmpty else {
                    throw PresentationParserError.unsafeRelationshipTarget(target)
                }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }
        let normalized = components.joined(separator: "/")
        guard isSafeArchivePath(normalized), normalized.hasPrefix(requiredPrefix) else {
            throw PresentationParserError.unsafeRelationshipTarget(target)
        }
        return normalized
    }

    private func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }
}

private struct TextRunResult: Sendable {
    let strings: [String]
    let characterCount: Int
}

private struct OfficeRelationship: Sendable {
    let id: String
    let target: String
    let type: String
    let isExternal: Bool
}

private final class PresentationOrderDelegate: NSObject, XMLParserDelegate {
    var relationshipIDs: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = qName ?? elementName
        guard name.hasSuffix(":sldId") || name == "sldId" else { return }
        if let relationshipID = attributeDict["r:id"] ?? attributeDict["id"] {
            relationshipIDs.append(relationshipID)
        }
    }
}

private final class RelationshipsDelegate: NSObject, XMLParserDelegate {
    var relationships: [OfficeRelationship] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard elementName == "Relationship" || qName == "Relationship" else { return }
        guard let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        relationships.append(
            OfficeRelationship(
                id: id,
                target: target,
                type: attributeDict["Type"] ?? "",
                isExternal: attributeDict["TargetMode"]?.lowercased() == "external"
            )
        )
    }
}

private final class TextRunsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    var exceededLimit = false
    private let maximumCharacters: Int
    private var characterCount = 0
    private var collectingText = false
    private var current = ""

    init(maximumCharacters: Int) {
        self.maximumCharacters = maximumCharacters
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = qName ?? elementName
        if name.hasSuffix(":t") || name == "t" {
            collectingText = true
            current = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard collectingText else { return }
        guard characterCount <= maximumCharacters - string.count else {
            exceededLimit = true
            parser.abortParsing()
            return
        }
        characterCount += string.count
        current.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = qName ?? elementName
        if name.hasSuffix(":t") || name == "t" {
            strings.append(current)
            collectingText = false
            current = ""
        }
    }
}
