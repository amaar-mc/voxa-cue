import Foundation
import Testing
import VoxaCore
import ZIPFoundation
@testable import VoxaRuntime

@Test("PowerPoint parsing follows presentation order and keeps speaker notes")
func powerPointParsingPreservesOrderAndNotes() throws {
    let url = temporaryURL(extension: "pptx")
    defer { try? FileManager.default.removeItem(at: url) }
    try writePowerPoint(
        to: url,
        slideRelationshipIDs: ["rIdSecond", "rIdFirst"],
        relationships: [
            ("rIdFirst", "slides/slide1.xml"),
            ("rIdSecond", "slides/slide2.xml")
        ],
        slides: [
            "ppt/slides/slide1.xml": textXML(["Closing", "Thank you"]),
            "ppt/slides/slide2.xml": textXML(["Opening", "The problem"]),
            "ppt/notesSlides/notesSlide2.xml": textXML(["Opening", "Pause after the hook"])
        ],
        extraEntries: [
            "ppt/slides/_rels/slide2.xml.rels": relationshipsXML([
                ("notes", "../notesSlides/notesSlide2.xml", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide")
            ])
        ]
    )

    let slides = try PresentationFileParser(limits: .production).parse(url: url)

    #expect(slides.map(\.index) == [0, 1])
    #expect(slides.map(\.title) == ["Opening", "Closing"])
    #expect(slides[0].body == "The problem")
    #expect(slides[0].notes == "Pause after the hook")
}

@Test("PowerPoint parsing rejects more than the configured slide limit")
func powerPointParsingRejectsTooManySlides() throws {
    let url = temporaryURL(extension: "pptx")
    defer { try? FileManager.default.removeItem(at: url) }
    try writePowerPoint(
        to: url,
        slideRelationshipIDs: ["one", "two"],
        relationships: [
            ("one", "slides/slide1.xml"),
            ("two", "slides/slide2.xml")
        ],
        slides: [:],
        extraEntries: [:]
    )
    let limits = parserLimits(maxSlideCount: 1, maxArchiveEntryBytes: 1_024)

    #expect(throws: PresentationParserError.tooManySlides(maximum: 1)) {
        try PowerPointParser(limits: limits).parse(url: url)
    }
}

@Test("PowerPoint parsing enforces the production 100-slide limit")
func powerPointParsingEnforcesProductionSlideLimit() throws {
    let url = temporaryURL(extension: "pptx")
    defer { try? FileManager.default.removeItem(at: url) }
    let ids = (1...101).map { "slide\($0)" }
    try writePowerPoint(
        to: url,
        slideRelationshipIDs: ids,
        relationships: ids.enumerated().map { (id: $0.element, target: "slides/slide\($0.offset + 1).xml") },
        slides: [:],
        extraEntries: [:]
    )

    #expect(throws: PresentationParserError.tooManySlides(maximum: 100)) {
        try PowerPointParser(limits: .production).parse(url: url)
    }
}

@Test("PowerPoint parsing rejects an oversized expanded XML entry before extraction")
func powerPointParsingRejectsOversizedEntry() throws {
    let url = temporaryURL(extension: "pptx")
    defer { try? FileManager.default.removeItem(at: url) }
    try writePowerPoint(
        to: url,
        slideRelationshipIDs: ["slide"],
        relationships: [("slide", "slides/slide1.xml")],
        slides: ["ppt/slides/slide1.xml": Data(repeating: 0x20, count: 257)],
        extraEntries: [:]
    )
    let limits = parserLimits(maxSlideCount: 100, maxArchiveEntryBytes: 256)

    #expect(throws: PresentationParserError.archiveEntryTooLarge(path: "ppt/slides/slide1.xml", maximumBytes: 256)) {
        try PowerPointParser(limits: limits).parse(url: url)
    }
}

@Test("PowerPoint parsing rejects an oversized aggregate expansion")
func powerPointParsingRejectsOversizedExpansion() throws {
    let url = temporaryURL(extension: "pptx")
    defer { try? FileManager.default.removeItem(at: url) }
    let archive = try Archive(url: url, accessMode: .create)
    try add(Data(repeating: 0x20, count: 200), path: "first.bin", to: archive)
    try add(Data(repeating: 0x20, count: 200), path: "second.bin", to: archive)
    let limits = PresentationParserLimits(
        maxSourceFileBytes: 10_000,
        maxSlideCount: 100,
        maxArchiveEntryCount: 100,
        maxArchiveEntryBytes: 256,
        maxArchiveExpandedBytes: 399,
        maxSlideTextCharacters: 100,
        maxExtractedTextCharacters: 200
    )

    #expect(throws: PresentationParserError.expandedArchiveTooLarge(maximumBytes: 399)) {
        try PowerPointParser(limits: limits).parse(url: url)
    }
}

@Test("PowerPoint parsing rejects unsafe relationship traversal")
func powerPointParsingRejectsUnsafeTraversal() throws {
    let url = temporaryURL(extension: "pptx")
    defer { try? FileManager.default.removeItem(at: url) }
    try writePowerPoint(
        to: url,
        slideRelationshipIDs: ["slide"],
        relationships: [("slide", "../../outside.xml")],
        slides: [:],
        extraEntries: [:]
    )

    #expect(throws: PresentationParserError.unsafeRelationshipTarget("../../outside.xml")) {
        try PowerPointParser(limits: .production).parse(url: url)
    }
}

@Test("PowerPoint parsing rejects extracted text beyond its budget")
func powerPointParsingRejectsOversizedText() throws {
    let url = temporaryURL(extension: "pptx")
    defer { try? FileManager.default.removeItem(at: url) }
    try writePowerPoint(
        to: url,
        slideRelationshipIDs: ["slide"],
        relationships: [("slide", "slides/slide1.xml")],
        slides: ["ppt/slides/slide1.xml": textXML([String(repeating: "a", count: 33)])],
        extraEntries: [:]
    )
    let limits = PresentationParserLimits(
        maxSourceFileBytes: 10_000,
        maxSlideCount: 100,
        maxArchiveEntryCount: 100,
        maxArchiveEntryBytes: 1_024,
        maxArchiveExpandedBytes: 10_000,
        maxSlideTextCharacters: 32,
        maxExtractedTextCharacters: 128
    )

    #expect(throws: PresentationParserError.extractedTextTooLarge(maximumCharacters: 32)) {
        try PowerPointParser(limits: limits).parse(url: url)
    }
}

@Test("PowerPoint parsing rejects malformed and empty packages")
func powerPointParsingRejectsMalformedAndEmptyPackages() throws {
    let malformedURL = temporaryURL(extension: "pptx")
    let emptyURL = temporaryURL(extension: "pptx")
    defer {
        try? FileManager.default.removeItem(at: malformedURL)
        try? FileManager.default.removeItem(at: emptyURL)
    }
    try Data("not a zip".utf8).write(to: malformedURL, options: .atomic)
    try writePowerPoint(
        to: emptyURL,
        slideRelationshipIDs: [],
        relationships: [],
        slides: [:],
        extraEntries: [:]
    )

    #expect(throws: PresentationParserError.malformedArchive) {
        try PowerPointParser(limits: .production).parse(url: malformedURL)
    }
    #expect(throws: PresentationParserError.noSlides) {
        try PowerPointParser(limits: .production).parse(url: emptyURL)
    }
}

@Test("PDF parsing preserves page order and extracts page text")
func pdfParsingPreservesPageOrder() throws {
    let url = temporaryURL(extension: "pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try makeTextPDF(pages: ["Opening idea", "Second idea"]).write(to: url, options: .atomic)

    let slides = try PDFPresentationParser(limits: .production).parse(url: url)

    #expect(slides.map(\.index) == [0, 1])
    #expect(slides.map(\.title) == ["Opening idea", "Second idea"])
}

@Test("PDF parsing rejects malformed and empty files")
func pdfParsingRejectsMalformedAndEmptyFiles() throws {
    let malformedURL = temporaryURL(extension: "pdf")
    let emptyURL = temporaryURL(extension: "pdf")
    defer {
        try? FileManager.default.removeItem(at: malformedURL)
        try? FileManager.default.removeItem(at: emptyURL)
    }
    try Data("not a PDF".utf8).write(to: malformedURL, options: .atomic)
    try makeEmptyPDF().write(to: emptyURL, options: .atomic)

    #expect(throws: PresentationParserError.malformedPDF) {
        try PDFPresentationParser(limits: .production).parse(url: malformedURL)
    }
    #expect(throws: PresentationParserError.malformedPDF) {
        try PDFPresentationParser(limits: .production).parse(url: emptyURL)
    }
}

@Test("Presentation parser accepts case-insensitive extensions and rejects other formats")
func presentationParserDispatchesByExtension() throws {
    let pdfURL = temporaryURL(extension: "PDF")
    let textURL = temporaryURL(extension: "txt")
    defer {
        try? FileManager.default.removeItem(at: pdfURL)
        try? FileManager.default.removeItem(at: textURL)
    }
    try makeTextPDF(pages: ["One page"]).write(to: pdfURL, options: .atomic)
    try Data("plain text".utf8).write(to: textURL, options: .atomic)

    #expect(try PresentationFileParser(limits: .production).parse(url: pdfURL).count == 1)
    #expect(throws: PresentationParserError.unsupportedFileExtension("txt")) {
        try PresentationFileParser(limits: .production).parse(url: textURL)
    }
}

private func parserLimits(maxSlideCount: Int, maxArchiveEntryBytes: UInt64) -> PresentationParserLimits {
    PresentationParserLimits(
        maxSourceFileBytes: 10_000,
        maxSlideCount: maxSlideCount,
        maxArchiveEntryCount: 100,
        maxArchiveEntryBytes: maxArchiveEntryBytes,
        maxArchiveExpandedBytes: 10_000,
        maxSlideTextCharacters: 1_000,
        maxExtractedTextCharacters: 2_000
    )
}

private func temporaryURL(extension pathExtension: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(pathExtension)
}

private func writePowerPoint(
    to url: URL,
    slideRelationshipIDs: [String],
    relationships: [(id: String, target: String)],
    slides: [String: Data],
    extraEntries: [String: Data]
) throws {
    let archive = try Archive(url: url, accessMode: .create)
    let order = slideRelationshipIDs.map { #"<p:sldId r:id="\#($0)"/>"# }.joined()
    try add(
        Data(#"<p:presentation xmlns:p="p" xmlns:r="r"><p:sldIdLst>\#(order)</p:sldIdLst></p:presentation>"#.utf8),
        path: "ppt/presentation.xml",
        to: archive
    )
    try add(
        relationshipsXML(relationships.map {
            ($0.id, $0.target, "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide")
        }),
        path: "ppt/_rels/presentation.xml.rels",
        to: archive
    )
    for (path, data) in slides.merging(extraEntries, uniquingKeysWith: { current, _ in current }) {
        try add(data, path: path, to: archive)
    }
}

private func add(_ data: Data, path: String, to archive: Archive) throws {
    try archive.addEntry(
        with: path,
        type: .file,
        uncompressedSize: Int64(data.count),
        compressionMethod: .deflate,
        bufferSize: 64,
        provider: { position, size in
            data.subdata(in: Int(position)..<(Int(position) + size))
        }
    )
}

private func textXML(_ strings: [String]) -> Data {
    let runs = strings.map { "<a:t>\(escapeXML($0))</a:t>" }.joined()
    return Data(#"<p:sld xmlns:p="p" xmlns:a="a">\#(runs)</p:sld>"#.utf8)
}

private func relationshipsXML(_ relationships: [(id: String, target: String, type: String)]) -> Data {
    let elements = relationships.map {
        #"<Relationship Id="\#($0.id)" Target="\#($0.target)" Type="\#($0.type)"/>"#
    }.joined()
    return Data(#"<Relationships>\#(elements)</Relationships>"#.utf8)
}

private func escapeXML(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func makeTextPDF(pages: [String]) -> Data {
    var objects: [String] = []
    let pageObjectNumbers = pages.indices.map { 3 + ($0 * 2) }
    objects.append("<< /Type /Catalog /Pages 2 0 R >>")
    let kids = pageObjectNumbers.map { "\($0) 0 R" }.joined(separator: " ")
    objects.append("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>")
    for (index, page) in pages.enumerated() {
        let pageNumber = pageObjectNumbers[index]
        let contentNumber = pageNumber + 1
        objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> /Contents \(contentNumber) 0 R >>")
        let content = "BT /F1 18 Tf 72 720 Td (\(escapePDF(page))) Tj ET"
        objects.append("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream")
    }
    return makePDF(objects: objects, rootObject: 1)
}

private func makeEmptyPDF() -> Data {
    makePDF(
        objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [] /Count 0 >>"
        ],
        rootObject: 1
    )
}

private func makePDF(objects: [String], rootObject: Int) -> Data {
    var data = Data("%PDF-1.4\n".utf8)
    var offsets: [Int] = [0]
    for (index, object) in objects.enumerated() {
        offsets.append(data.count)
        data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xrefOffset = data.count
    data.append(Data("xref\n0 \(objects.count + 1)\n".utf8))
    data.append(Data("0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() {
        data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root \(rootObject) 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
}

private func escapePDF(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "(", with: "\\(")
        .replacingOccurrences(of: ")", with: "\\)")
}
