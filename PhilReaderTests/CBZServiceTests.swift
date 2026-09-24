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

        let pages = try await CBZService.shared.extractAllPages(from: url)
        XCTAssertEqual(pages.map { String(decoding: $0, as: UTF8.self) }, ["one", "two", "ten"])
    }

    func testCoverIsFirstSortedPage() async throws {
        let url = try makeCBZ([
            ("chapter1/002.webp", Data("second".utf8)),
            ("chapter1/001.webp", Data("first".utf8)),
        ])
        let cover = try await CBZService.shared.extractCover(from: url)
        XCTAssertEqual(cover.map { String(decoding: $0, as: UTF8.self) }, "first")
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
