import UIKit
import XCTest
@testable import PhilReader

final class FormatTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Detection

    func testDetectsFormats() throws {
        XCTAssertEqual(ComicFormat(url: URL(fileURLWithPath: "/x/Book.CBZ")), .cbz)
        XCTAssertEqual(ComicFormat(url: URL(fileURLWithPath: "/x/Book.zip")), .cbz)
        XCTAssertEqual(ComicFormat(url: URL(fileURLWithPath: "/x/Book.pdf")), .pdf)
        XCTAssertNil(ComicFormat(url: URL(fileURLWithPath: "/x/Book.txt")))
        XCTAssertEqual(ComicFormat(url: tempDir), .folder)
        XCTAssertThrowsError(try ComicSources.open(URL(fileURLWithPath: "/x/Book.txt")))
    }

    // MARK: - PDF

    func testPDFPagesRenderUprightAtRequestedSize() async throws {
        let url = tempDir.appendingPathComponent("book.pdf")
        try makePDF(pages: 3).write(to: url)
        let source = try ComicSources.open(url)
        XCTAssertEqual(source.pageCount, 3)

        let rendered = await source.image(at: 0, maxPixelSize: 800, maxWidth: nil)
        let page = try XCTUnwrap(rendered)
        XCTAssertEqual(page.cgImage?.width, 600)
        XCTAssertEqual(page.cgImage?.height, 800)
        // The PDF's top half is red: the render must not be upside down.
        XCTAssertGreaterThan(color(of: page, x: 300, y: 50).r, 200)
        XCTAssertLessThan(color(of: page, x: 300, y: 50).g, 60)
        XCTAssertGreaterThan(color(of: page, x: 300, y: 750).g, 200, "Bottom half should be white")

        let narrow = await source.image(at: 1, maxPixelSize: 800, maxWidth: 150)
        XCTAssertEqual(narrow?.cgImage?.width, 150)
        XCTAssertEqual(narrow?.cgImage?.height, 200)

        let missing = await source.image(at: 3, maxPixelSize: 800, maxWidth: nil)
        XCTAssertNil(missing)
    }

    func testPDFMetadataComesFromDocumentInfo() async throws {
        let url = tempDir.appendingPathComponent("info.pdf")
        try makePDF(pages: 1, title: "Starfall Omnibus", author: "Rumi Tanaka").write(to: url)
        let metadata = await ComicSources.metadata(for: url)
        XCTAssertEqual(metadata?.title, "Starfall Omnibus")
        XCTAssertEqual(metadata?.writer, "Rumi Tanaka")
    }

    // MARK: - Folder

    func testFolderPagesAreNaturallySortedIncludingSubfolders() async throws {
        let folder = tempDir.appendingPathComponent("My Comic", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("extras"), withIntermediateDirectories: true)
        try png(width: 20).write(to: folder.appendingPathComponent("10.png"))
        try png(width: 10).write(to: folder.appendingPathComponent("2.png"))
        try png(width: 30).write(to: folder.appendingPathComponent("extras/1.png"))
        try Data("notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        try Data("<ComicInfo><Series>Moonlit</Series></ComicInfo>".utf8)
            .write(to: folder.appendingPathComponent("ComicInfo.xml"))

        let source = try ComicSources.open(folder)
        XCTAssertEqual(source.pageCount, 3)
        var widths: [Int?] = []
        for index in 0..<3 {
            let image = await source.image(at: index, maxPixelSize: 1000, maxWidth: nil)
            widths.append(image?.cgImage?.width)
        }
        XCTAssertEqual(widths, [10, 20, 30])

        let metadata = await ComicSources.metadata(for: folder)
        XCTAssertEqual(metadata?.series, "Moonlit")
    }

    // MARK: - CB7 and CBR

    func testCB7PagesAndMetadata() async throws {
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).cb7")
        defer { ExtractedArchive.remove(for: url) }
        try await assertSolidArchive(url, fixture: Fixtures.sevenZip)
    }

    func testCBRPagesAndMetadata() async throws {
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).cbr")
        defer { ExtractedArchive.remove(for: url) }
        try await assertSolidArchive(url, fixture: Fixtures.rar)
    }

    func testSevenZipExtractorWritesPagesOnly() throws {
        let archive = tempDir.appendingPathComponent("\(UUID().uuidString).cb7")
        let folder = tempDir.appendingPathComponent("out", isDirectory: true)
        try step("write fixture") { try Data(base64Encoded: Fixtures.sevenZip.joined())!.write(to: archive) }
        try step("create folder") { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try step("extract") { try SevenZipExtractor.extract(archive, into: folder) }
        let written = try step("list") { try FileManager.default.subpathsOfDirectory(atPath: folder.path).sorted() }
        XCTAssertEqual(written.filter { $0.hasSuffix(".png") || $0.hasSuffix(".xml") },
                       ["ComicInfo.xml", "pages/10.png", "pages/2.png", "pages/extra/1.png"])
        XCTAssertFalse(written.contains("notes.txt"))
    }

    func testCorruptCBRThrows() throws {
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).cbr")
        try Data("Rar! but not really".utf8).write(to: url)
        XCTAssertThrowsError(try ComicSources.open(url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ExtractedArchive.folderURL(for: url).path))
    }

    /// Both fixtures hold pages/10.png (20px wide), pages/2.png (10px), pages/extra/1.png (30px),
    /// notes.txt and ComicInfo.xml for Starfall #4.
    private func assertSolidArchive(_ url: URL, fixture: [String],
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        try step("write fixture") { try Data(base64Encoded: fixture.joined())!.write(to: url) }
        let source = try step("open") { try ComicSources.open(url) }
        XCTAssertEqual(source.pageCount, 3, file: file, line: line)
        var widths: [Int?] = []
        for index in 0..<source.pageCount {
            let image = await source.image(at: index, maxPixelSize: 1000, maxWidth: nil)
            widths.append(image?.cgImage?.width)
        }
        XCTAssertEqual(widths, [10, 20, 30], file: file, line: line)

        let metadata = await ComicSources.metadata(for: url)
        XCTAssertEqual(metadata?.series, "Starfall", file: file, line: line)
        XCTAssertEqual(metadata?.number, "4", file: file, line: line)

        // A second open reuses the unpacked folder.
        XCTAssertEqual(try step("reopen") { try ComicSources.open(url) }.pageCount, 3, file: file, line: line)
    }

    /// Runs one step, failing with the step's name and the full error so CI logs say exactly what broke.
    @discardableResult
    private func step<T>(_ name: String, file: StaticString = #filePath, line: UInt = #line,
                         _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            XCTFail("\(name) failed: \(error) \((error as NSError).userInfo)", file: file, line: line)
            throw error
        }
    }

    // MARK: - Helpers

    private func makePDF(pages: Int, title: String? = nil, author: String? = nil) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        var info: [String: Any] = [:]
        if let title { info[kCGPDFContextTitle as String] = title }
        if let author { info[kCGPDFContextAuthor as String] = author }
        format.documentInfo = info
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 400)
        return UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            for _ in 0..<pages {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(bounds)
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            }
        }
    }

    private func png(width: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: 40), format: format).pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: 40))
        }
    }

    /// Reads one pixel, with `y` measured from the top of the image.
    private func color(of image: UIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        guard let cgImage = image.cgImage else { return (0, 0, 0) }
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cgImage, in: CGRect(x: -x, y: -(cgImage.height - 1 - y),
                                              width: cgImage.width, height: cgImage.height))
        }
        return (pixel[0], pixel[1], pixel[2])
    }
}

/// Tiny archives made with py7zr (7-Zip, LZMA2 only, no BCJ filter) and a hand-built stored RAR5
/// (verified with Python's rarfile), since neither format can be written on iOS.
private enum Fixtures {
    static let sevenZip = [
        "N3q8ryccAAQ0aNw0cQEAAAAAAAAXAAAAAAAAAFjXyw/gASQAtV0ARJQFxHon9vfuiY5QkIizqtVQJVKKnK/FRCMRZhU/580b",
        "WLhSEifFVUh4LM9XCtD6nQlSLt3ZI4euuluLJYXLkCO2Ea7gPUAdxgMpzkii59D4DJcw+AKg6isefJNajrDaPFhIhziOInm3",
        "oHlEUnB3pumHKvMde/dj+4FDZSEzpMuiHvKavkmEIrNGSW4VfzXINIcJEgCH6LTz8t5HuRRpieFl9O+AFiGOtS6AXAuthoHW",
        "q0DvAADgAQcArF0AAIEzB64P1TEBfFck0/6zcBaxhoj/bxiLD/TAFsyV5qnmNrAEEnRly8fp2XTfLF4fXqZ++qEykfrMc3II",
        "zGqlZKu5FLIAlw+mpHUdRzNKsVJoS6E9aB5s4Hza4RTdEwNY7fnMANDD0m1crHfKLN5lNpjCyLe3S1BeA78A9cV9EftKbMSO",
        "iP717bCiD5qVjtgg1qmO+n+JeFlQ5QwaPlkECiXoKX7AFRqREAAAAAAXBoC9AQmAtAAHCwEAASEhARgMgQgAAA==",
    ]

    static let rar = [
        "UmFyIRoHAQDFGjMyAwEAAAevxTgZAgJJBEkg6U4t/gAADHBhZ2VzLzEwLnBuZ4lQTkcNChoKAAAADUlIRFIAAAAUAAAABAgC",
        "AAAAAT2IwQAAABBJREFUeJxjYGD4TwEakpoBrU9PsW9yn1EAAAAASUVORK5CYIL/ZiZ0GAICSQRJIPdxYMwAAAtwYWdlcy8y",
        "LnBuZ4lQTkcNChoKAAAADUlIRFIAAAAKAAAABAgCAAAAOFo5mgAAABBJREFUeJxjYGD4jxfRUBoAf3sn2db7djsAAAAASUVO",
        "RK5CYILDXDgUHgICSwRLIFZEFq8AABFwYWdlcy9leHRyYS8xLnBuZ4lQTkcNChoKAAAADUlIRFIAAAAeAAAABAgCAAAAFh8Y",
        "CAAAABJJREFUeJxjYGD4TzM0ajQKAgCJgHeJg8kYXgAAAABJRU5ErkJggnl/btIWAgIGBAYg4taIDQAACW5vdGVzLnR4dGln",
        "bm9yZW+CuyYaAgJCBEIg8kZYHwAADUNvbWljSW5mby54bWw8Q29taWNJbmZvPjxTZXJpZXM+U3RhcmZhbGw8L1Nlcmllcz48",
        "TnVtYmVyPjQ8L051bWJlcj48L0NvbWljSW5mbz4Zsjo1AwUAAA==",
    ]
}
