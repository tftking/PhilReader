import UIKit
import XCTest
@testable import PhilReader

final class PanelDetectorTests: XCTestCase {
    /// A classic three-tier page: wide panel, two side by side, wide panel.
    private let grid = [
        CGRect(x: 40, y: 40, width: 520, height: 260),
        CGRect(x: 40, y: 330, width: 240, height: 260),
        CGRect(x: 310, y: 330, width: 250, height: 260),
        CGRect(x: 40, y: 620, width: 520, height: 240),
    ]

    private func assertPanels(_ found: [CGRect], match expected: [CGRect],
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(found.count, expected.count, "Found \(found)", file: file, line: line)
        for (panel, rect) in zip(found, expected) {
            let normalised = CGRect(x: rect.minX / 600, y: rect.minY / 900, width: rect.width / 600, height: rect.height / 900)
            XCTAssertEqual(panel.minX, normalised.minX, accuracy: 0.02, file: file, line: line)
            XCTAssertEqual(panel.minY, normalised.minY, accuracy: 0.02, file: file, line: line)
            XCTAssertEqual(panel.width, normalised.width, accuracy: 0.03, file: file, line: line)
            XCTAssertEqual(panel.height, normalised.height, accuracy: 0.03, file: file, line: line)
        }
    }

    func testFindsGridPanelsInReadingOrder() {
        let page = TestImages.page(panels: grid)
        assertPanels(PanelDetector.panels(in: page, rightToLeft: false), match: grid)
    }

    func testMangaReadsRowsRightToLeft() {
        let page = TestImages.page(panels: grid)
        assertPanels(PanelDetector.panels(in: page, rightToLeft: true), match: [grid[0], grid[2], grid[1], grid[3]])
    }

    func testBlackGuttersWork() {
        let page = TestImages.page(panels: grid, background: .black, border: .white)
        assertPanels(PanelDetector.panels(in: page, rightToLeft: false), match: grid)
    }

    func testFullBleedArtIsOnePanel() {
        let page = TestImages.page(panels: [CGRect(x: 0, y: 0, width: 600, height: 900)])
        let panels = PanelDetector.panels(in: page, rightToLeft: false)
        XCTAssertEqual(panels.count, 1)
        XCTAssertEqual(panels.first?.width ?? 0, 1, accuracy: 0.05)
    }
}

final class EPUBTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeEPUB() throws -> URL {
        let container = """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Starfall Omnibus</dc:title>
            <dc:creator>Rumi Tanaka</dc:creator>
          </metadata>
          <manifest>
            <item id="p2" href="pages/p2.xhtml" media-type="application/xhtml+xml"/>
            <item id="p1" href="pages/p1.xhtml" media-type="application/xhtml+xml"/>
            <item id="art" href="images/c.png" media-type="image/png"/>
            <item id="a" href="images/a%20x.png" media-type="image/png"/>
            <item id="b" href="images/b.png" media-type="image/png"/>
          </manifest>
          <spine page-progression-direction="rtl">
            <itemref idref="p1"/>
            <itemref idref="p2"/>
            <itemref idref="art"/>
          </spine>
        </package>
        """
        let page1 = #"<html xmlns="http://www.w3.org/1999/xhtml"><body><img alt="" src="../images/b.png"/></body></html>"#
        let page2 = #"<html><body><svg xmlns:xlink="http://www.w3.org/1999/xlink"><image width="1" height="1" xlink:href="../images/a%20x.png"/></svg></body></html>"#
        let url = tempDir.appendingPathComponent("book.epub")
        try TestZip.data([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/pages/p1.xhtml", Data(page1.utf8)),
            ("OEBPS/pages/p2.xhtml", Data(page2.utf8)),
            ("OEBPS/images/a x.png", TestImages.png(width: 10)),
            ("OEBPS/images/b.png", TestImages.png(width: 20)),
            ("OEBPS/images/c.png", TestImages.png(width: 30)),
        ]).write(to: url)
        return url
    }

    func testPagesFollowTheSpine() async throws {
        let source = try ComicSources.open(try makeEPUB())
        XCTAssertEqual(source.pageCount, 3)
        var widths: [Int?] = []
        for index in 0..<source.pageCount {
            let image = await source.image(at: index, maxPixelSize: 1000, maxWidth: nil)
            widths.append(image?.cgImage?.width)
        }
        XCTAssertEqual(widths, [20, 10, 30], "p1 → b.png, p2 → 'a x.png' via SVG, then the bare image")
    }

    func testMetadataAndDirection() async throws {
        let metadata = await ComicSources.metadata(for: try makeEPUB())
        XCTAssertEqual(metadata?.title, "Starfall Omnibus")
        XCTAssertEqual(metadata?.writer, "Rumi Tanaka")
        XCTAssertEqual(metadata?.readsRightToLeft, true)
    }

    func testResolvesRelativePaths() {
        XCTAssertEqual(EPUBParser.resolve("../images/a%20b.jpg#page", from: "OEBPS/text"), "OEBPS/images/a b.jpg")
        XCTAssertEqual(EPUBParser.resolve("./p.xhtml", from: ""), "p.xhtml")
        XCTAssertEqual(EPUBParser.resolve("/root.png", from: "OEBPS"), "root.png")
    }

    func testDetectsEPUBFormat() {
        XCTAssertEqual(ComicFormat(url: URL(fileURLWithPath: "/x/Book.EPUB")), .epub)
    }
}

final class VerticalZoomTests: XCTestCase {
    func testScaleStaysInRange() {
        XCTAssertEqual(VerticalZoom.clampedScale(0.5), 1)
        XCTAssertEqual(VerticalZoom.clampedScale(2.2), 2.2)
        XCTAssertEqual(VerticalZoom.clampedScale(9), 3)
    }

    func testPanKeepsTheStripCoveringTheScreen() {
        XCTAssertEqual(VerticalZoom.clampedPan(50, scale: 1, width: 400), 0, "No panning when not zoomed")
        XCTAssertEqual(VerticalZoom.clampedPan(150, scale: 2, width: 400), 150)
        XCTAssertEqual(VerticalZoom.clampedPan(500, scale: 2, width: 400), 200)
        XCTAssertEqual(VerticalZoom.clampedPan(-500, scale: 3, width: 400), -400)
    }
}

final class ReaderPreferenceTests: XCTestCase {
    func testTapZonesFollowReadingDirection() {
        func outcome(_ x: CGFloat, rtl: Bool, left: EdgeTapAction = .turnTowardSide,
                     right: EdgeTapAction = .turnTowardSide) -> TapZones.Outcome {
            TapZones.outcome(atFraction: x, zone: 0.3, left: left, right: right, rightToLeft: rtl)
        }
        XCTAssertEqual(outcome(0.1, rtl: false), .backward)
        XCTAssertEqual(outcome(0.9, rtl: false), .forward)
        XCTAssertEqual(outcome(0.1, rtl: true), .forward, "Manga: the left side moves forward")
        XCTAssertEqual(outcome(0.9, rtl: true), .backward)
        XCTAssertEqual(outcome(0.5, rtl: false), .toggleControls)
        XCTAssertEqual(outcome(0.1, rtl: true, left: .nextPage), .forward)
        XCTAssertEqual(outcome(0.9, rtl: false, right: .nothing), .nothing)
        XCTAssertEqual(outcome(0.9, rtl: false, right: .toggleControls), .toggleControls)
        XCTAssertEqual(TapZones.outcome(atFraction: 0.25, zone: 0.2, left: .nextPage, right: .nextPage,
                                        rightToLeft: false), .toggleControls, "Outside a narrow zone")
    }

    func testPresetsRoundTripThroughDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ReaderPreferenceTests"))
        defaults.removePersistentDomain(forName: "ReaderPreferenceTests")
        var webtoon = try XCTUnwrap(ReaderPreset.builtIn.first { $0.name == "Webtoon" })
        webtoon.filters = ImageFilterSettings(brightness: 0.1, contrast: 1.2, tone: .sepia)
        webtoon.apply(to: defaults)

        let current = ReaderPreset.current(named: "Copy", in: defaults)
        XCTAssertEqual(current.mode, .vertical)
        XCTAssertEqual(current.fit, PageFit.width.rawValue)
        XCTAssertFalse(current.rightToLeft)
        XCTAssertEqual(current.filters, webtoon.filters)
        XCTAssertTrue(defaults.bool(forKey: ReaderKeys.filtersEnabled))

        let list = PresetList([current])
        XCTAssertEqual(PresetList(rawValue: list.rawValue), list)
        XCTAssertNil(PresetList(rawValue: "not json"))
    }

    func testReadingTimeFormatting() {
        XCTAssertEqual(ReaderView.duration(65), "1:05")
        XCTAssertEqual(ReaderView.duration(3_729), "1:02:09")
        XCTAssertEqual(ReaderView.duration(-4), "0:00")
    }

    func testOlderLibrariesDecodeWithoutReadingTime() throws {
        let comic = ComicBook(title: "A", fileName: "a.cbz", pageCount: 3)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(comic)) as? [String: Any])
        json["readingTime"] = nil
        let decoded = try JSONDecoder().decode(ComicBook.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.readingTime, 0)
    }
}

final class WebServerTests: XCTestCase {
    func testParsesARequestHead() {
        let raw = "POST /upload?x=1 HTTP/1.1\r\nHost: phone\r\nContent-Length: 42\r\nX-File-Name: Starfall%201.cbz\r\n\r\nBODY"
        guard case .complete(let head, let offset) = HTTPRequestHead.parse(Data(raw.utf8)) else {
            return XCTFail("Expected a complete head")
        }
        XCTAssertEqual(head.method, "POST")
        XCTAssertEqual(head.path, "/upload")
        XCTAssertEqual(head.contentLength, 42)
        XCTAssertEqual(head.uploadFileName, "Starfall 1.cbz")
        XCTAssertEqual(String(decoding: Data(raw.utf8)[offset...], as: UTF8.self), "BODY")
    }

    func testWaitsForTheWholeHead() {
        XCTAssertEqual(HTTPRequestHead.parse(Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)), .incomplete)
        XCTAssertEqual(HTTPRequestHead.parse(Data("NONSENSE\r\n\r\n".utf8)), .malformed)
    }

    func testRejectsUnsafeOrUnsupportedFileNames() {
        func name(_ header: String) -> String? {
            HTTPRequestHead(method: "POST", path: "/upload", headers: ["x-file-name": header]).uploadFileName
        }
        XCTAssertEqual(name("..%2F..%2Fetc%2FStarfall.cbr"), "Starfall.cbr", "Only the last path component is kept")
        XCTAssertEqual(name("Moonlit.EPUB"), "Moonlit.EPUB")
        XCTAssertNil(name("notes.txt"))
        XCTAssertNil(name(".hidden.cbz"))
        XCTAssertNil(name(""))
    }
}
