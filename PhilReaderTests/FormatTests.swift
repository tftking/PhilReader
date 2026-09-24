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
