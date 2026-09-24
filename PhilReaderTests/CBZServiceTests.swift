import UIKit
import XCTest
@testable import PhilReader

final class CBZServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testPagesAreNaturallySortedAndNonImagesIgnored() async throws {
        let url = try makeCBZ([
            ("page10.png", Data("ten".utf8)),
            ("page2.JPG", Data("two".utf8)),
            ("notes.txt", Data("ignore me".utf8)),
            ("__MACOSX/._page1.png", Data("resource fork".utf8)),
            ("page1.png", Data("one".utf8)),
        ])

        let count = try await CBZService.shared.pageCount(in: url)
        XCTAssertEqual(count, 3)

        let document = try CBZDocument(url: url)
        XCTAssertEqual(document.pageCount, 3)
        var pages: [String] = []
        for index in 0..<document.pageCount {
            pages.append(String(decoding: try await document.pageData(at: index), as: UTF8.self))
        }
        XCTAssertEqual(pages, ["one", "two", "ten"])
    }

    func testDocumentReadsPagesOnDemandInAnyOrder() async throws {
        let url = try makeCBZ((1...5).map { ("p\($0).png", Data("page \($0)".utf8)) })
        let document = try CBZDocument(url: url)

        let last = try await document.pageData(at: 4)
        let first = try await document.pageData(at: 0)
        XCTAssertEqual(String(decoding: last, as: UTF8.self), "page 5")
        XCTAssertEqual(String(decoding: first, as: UTF8.self), "page 1")
    }

    func testDocumentRejectsOutOfRangePage() async throws {
        let url = try makeCBZ([("p1.png", Data("one".utf8))])
        let document = try CBZDocument(url: url)
        do {
            _ = try await document.pageData(at: 1)
            XCTFail("Expected an out-of-range error")
        } catch CBZError.pageOutOfRange(let index) {
            XCTAssertEqual(index, 1)
        }
    }

    func testDocumentDecodesAndDownsamplesPages() async throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
        }
        let url = try makeCBZ([("tall.png", png), ("broken.png", Data("not an image".utf8))])
        let document = try CBZDocument(url: url)

        let downsampled = await document.image(at: 1, maxPixelSize: 200)
        let image = try XCTUnwrap(downsampled)
        XCTAssertEqual(image.cgImage?.width, 100)
        XCTAssertEqual(image.cgImage?.height, 200)

        let fullSize = await document.image(at: 1, maxPixelSize: 5000)
        let full = try XCTUnwrap(fullSize)
        XCTAssertEqual(full.cgImage?.height, 800, "Should never upscale")

        let broken = await document.image(at: 0, maxPixelSize: 200)
        XCTAssertNil(broken)
    }

    func testCoverIsFirstSortedPage() async throws {
        let url = try makeCBZ([
            ("chapter1/002.webp", Data("second".utf8)),
            ("chapter1/001.webp", Data("first".utf8)),
        ])
        let cover = try await CBZService.shared.extractCover(from: url)
        XCTAssertEqual(cover.map { String(decoding: $0, as: UTF8.self) }, "first")
    }

    func testReadsComicInfoMetadata() async throws {
        let xml = "<ComicInfo><Series>Starfall</Series><Number>1</Number></ComicInfo>"
        let url = try makeCBZ([("ComicInfo.xml", Data(xml.utf8)), ("001.png", Data("page".utf8))])
        let metadata = await CBZService.shared.metadata(in: url)
        XCTAssertEqual(metadata?.series, "Starfall")
        XCTAssertEqual(metadata?.number, "1")

        let count = try await CBZService.shared.pageCount(in: url)
        XCTAssertEqual(count, 1, "ComicInfo.xml must not count as a page")
    }

    func testInvalidArchiveThrows() async throws {
        let url = tempDir.appendingPathComponent("broken.cbz")
        try Data("not a zip".utf8).write(to: url)
        do {
            _ = try await CBZService.shared.pageCount(in: url)
            XCTFail("Expected an error for a non-ZIP file")
        } catch {
            XCTAssertTrue(error is CBZError)
        }
    }

    // MARK: - Minimal ZIP writer (stored, no compression)

    private func makeCBZ(_ entries: [(String, Data)]) throws -> URL {
        var body = Data()
        var central = Data()
        for (name, content) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(content)
            let offset = UInt32(body.count)

            body.append(le32(0x04034b50))
            body.append(le16(20)); body.append(le16(0)); body.append(le16(0))  // version, flags, stored
            body.append(le16(0)); body.append(le16(0x21))                      // mod time/date
            body.append(le32(crc)); body.append(le32(UInt32(content.count))); body.append(le32(UInt32(content.count)))
            body.append(le16(UInt16(nameData.count))); body.append(le16(0))
            body.append(nameData); body.append(content)

            central.append(le32(0x02014b50))
            central.append(le16(20)); central.append(le16(20)); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(crc)); central.append(le32(UInt32(content.count))); central.append(le32(UInt32(content.count)))
            central.append(le16(UInt16(nameData.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0o100644 << 16))
            central.append(le32(offset)); central.append(nameData)
        }
        var end = Data()
        end.append(le32(0x06054b50)); end.append(le16(0)); end.append(le16(0))
        end.append(le16(UInt16(entries.count))); end.append(le16(UInt16(entries.count)))
        end.append(le32(UInt32(central.count))); end.append(le32(UInt32(body.count))); end.append(le16(0))

        let url = tempDir.appendingPathComponent("\(UUID().uuidString).cbz")
        try (body + central + end).write(to: url)
        return url
    }

    private func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }
}
