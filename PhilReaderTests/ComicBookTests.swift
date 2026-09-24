import XCTest
@testable import PhilReader

final class ComicBookTests: XCTestCase {
    func testProgressIsZeroForSinglePageComic() {
        var comic = ComicBook(title: "One-shot", fileName: "a.cbz", pageCount: 1)
        comic.currentPage = 0
        XCTAssertEqual(comic.progress, 0)
    }

    func testProgressReachesOneOnLastPage() {
        var comic = ComicBook(title: "Vol 1", fileName: "a.cbz", pageCount: 11)
        comic.currentPage = 5
        XCTAssertEqual(comic.progress, 0.5, accuracy: 0.0001)
        comic.currentPage = 10
        XCTAssertEqual(comic.progress, 1, accuracy: 0.0001)
    }

    func testCodableRoundTrip() throws {
        var comic = ComicBook(title: "Vol 2", fileName: "b.cbz", pageCount: 20)
        comic.currentPage = 7
        let decoded = try JSONDecoder().decode(ComicBook.self, from: JSONEncoder().encode(comic))
        XCTAssertEqual(decoded.id, comic.id)
        XCTAssertEqual(decoded.title, "Vol 2")
        XCTAssertEqual(decoded.currentPage, 7)
        XCTAssertEqual(decoded.pageCount, 20)
    }
}
