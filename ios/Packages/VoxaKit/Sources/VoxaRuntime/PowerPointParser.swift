import Foundation
import VoxaCore
import ZIPFoundation

public enum PowerPointParserError: Error, Equatable {
    case missingPresentation
    case missingRelationships
    case noSlides
    case malformedXML(String)
}

public struct PowerPointParser: Sendable {
    public init() {}

    public func parse(url: URL) throws -> [DeckSlide] {
        let archive = try Archive(url: url, accessMode: .read)
        let presentationData = try data(in: archive, path: "ppt/presentation.xml")
        let relationshipData = try data(in: archive, path: "ppt/_rels/presentation.xml.rels")
        let slideRelationshipIDs = try presentationOrder(data: presentationData)
        let presentationRelationships = try relationships(data: relationshipData)

        let slidePaths = slideRelationshipIDs.compactMap { relationshipID -> String? in
            guard let target = presentationRelationships[relationshipID]?.target else { return nil }
            return normalizedArchivePath(basePath: "ppt/presentation.xml", target: target)
        }
        guard !slidePaths.isEmpty else { throw PowerPointParserError.noSlides }

        return try slidePaths.enumerated().map { offset, slidePath in
            let slideData = try data(in: archive, path: slidePath)
            let strings = try textRuns(data: slideData)
            let title = strings.first ?? "Slide \(offset + 1)"
            let body = strings.dropFirst().joined(separator: " ")
            let notes = try notesText(in: archive, slidePath: slidePath, slideStrings: Set(strings))
            return DeckSlide(
                id: UUID(),
                index: offset,
                title: title,
                body: body,
                notes: notes
            )
        }
    }

    private func notesText(in archive: Archive, slidePath: String, slideStrings: Set<String>) throws -> String {
        let slideURL = URL(fileURLWithPath: slidePath)
        let relationshipsPath = slideURL.deletingLastPathComponent()
            .appendingPathComponent("_rels")
            .appendingPathComponent(slideURL.lastPathComponent + ".rels")
            .path
        guard archive[relationshipsPath] != nil else { return "" }
        let relationData = try data(in: archive, path: relationshipsPath)
        let relationMap = try relationships(data: relationData)
        guard let notesRelation = relationMap.values.first(where: { $0.type.hasSuffix("/notesSlide") }) else {
            return ""
        }
        let notesPath = normalizedArchivePath(basePath: slidePath, target: notesRelation.target)
        guard archive[notesPath] != nil else { return "" }
        let notesRuns = try textRuns(data: data(in: archive, path: notesPath))
        return notesRuns.filter { !slideStrings.contains($0) }.joined(separator: " ")
    }

    private func data(in archive: Archive, path: String) throws -> Data {
        guard let entry = archive[path] else {
            if path == "ppt/presentation.xml" { throw PowerPointParserError.missingPresentation }
            throw PowerPointParserError.missingRelationships
        }
        var result = Data()
        _ = try archive.extract(entry, consumer: { chunk in result.append(chunk) })
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
        return Dictionary(uniqueKeysWithValues: delegate.relationships.map { ($0.id, $0) })
    }

    private func textRuns(data: Data) throws -> [String] {
        let delegate = TextRunsDelegate()
        try parse(data: data, delegate: delegate)
        return delegate.strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parse(data: Data, delegate: XMLParserDelegate) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw PowerPointParserError.malformedXML(parser.parserError?.localizedDescription ?? "Unknown XML error")
        }
    }

    private func normalizedArchivePath(basePath: String, target: String) -> String {
        let baseDirectory = (basePath as NSString).deletingLastPathComponent
        let combined = (baseDirectory as NSString).appendingPathComponent(target)
        return (combined as NSString).standardizingPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct OfficeRelationship: Sendable {
    let id: String
    let target: String
    let type: String
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
        relationships.append(OfficeRelationship(id: id, target: target, type: attributeDict["Type"] ?? ""))
    }
}

private final class TextRunsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var collectingText = false
    private var current = ""

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
        if collectingText { current.append(string) }
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

