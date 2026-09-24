import XCTest
@testable import PhilReader

final class ComicInfoParserTests: XCTestCase {
    func testParsesComicRackFields() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <Title>The Long Night</Title>
          <Series>Starfall</Series>
          <Number>3</Number>
          <Volume>1</Volume>
          <Summary>  A ship goes dark.  </Summary>
          <Writer>A. Writer</Writer>
          <Penciller>B. Artist</Penciller>
          <Publisher>Indie Press</Publisher>
          <Year>2024</Year>
          <Manga>YesAndRightToLeft</Manga>
          <Pages><Page Image="0" Type="FrontCover"/></Pages>
        </ComicInfo>
        """
        let metadata = try XCTUnwrap(ComicInfoParser.parse(Data(xml.utf8)))
        XCTAssertEqual(metadata.title, "The Long Night")
        XCTAssertEqual(metadata.series, "Starfall")
        XCTAssertEqual(metadata.number, "3")
        XCTAssertEqual(metadata.volume, 1)
        XCTAssertEqual(metadata.summary, "A ship goes dark.")
        XCTAssertEqual(metadata.writer, "A. Writer")
        XCTAssertEqual(metadata.artist, "B. Artist")
        XCTAssertEqual(metadata.publisher, "Indie Press")
        XCTAssertEqual(metadata.year, 2024)
        XCTAssertEqual(metadata.readsRightToLeft, true)
    }

    func testMangaDirection() {
        func direction(_ value: String) -> Bool? {
            ComicInfoParser.parse(Data("<ComicInfo><Manga>\(value)</Manga></ComicInfo>".utf8))?.readsRightToLeft
        }
        XCTAssertEqual(direction("YesAndRightToLeft"), true)
        XCTAssertEqual(direction("No"), false)
        XCTAssertNil(direction("Yes"))
    }

    func testEmptyOrInvalidXMLGivesNil() {
        XCTAssertNil(ComicInfoParser.parse(Data("<ComicInfo></ComicInfo>".utf8)))
        XCTAssertNil(ComicInfoParser.parse(Data("not xml".utf8)))
    }
}

final class LibraryQueryTests: XCTestCase {
    private func comic(_ title: String, page: Int = 0, pages: Int = 10, finished: Bool = false,
                       opened: TimeInterval? = nil, added: TimeInterval = 0,
                       metadata: ComicMetadata? = nil) -> ComicBook {
        var comic = ComicBook(title: title, fileName: "\(title).cbz", pageCount: pages, metadata: metadata)
        comic.currentPage = page
        comic.isFinished = finished
        comic.lastOpened = opened.map { Date(timeIntervalSince1970: $0) }
        comic.dateAdded = Date(timeIntervalSince1970: added)
        return comic
    }

    func testStatus() {
        XCTAssertEqual(comic("a").status, .unread)
        XCTAssertEqual(comic("b", page: 3).status, .inProgress)
        XCTAssertEqual(comic("c", opened: 10).status, .inProgress)
        XCTAssertEqual(comic("d", page: 3, finished: true).status, .finished)
        XCTAssertEqual(comic("d", page: 3, finished: true).progress, 1)
    }

    func testFilters() {
        let comics = [comic("unread"), comic("reading", page: 2), comic("done", finished: true)]
        XCTAssertEqual(LibraryQuery(filter: .unread).apply(to: comics).map(\.title), ["unread"])
        XCTAssertEqual(LibraryQuery(filter: .inProgress).apply(to: comics).map(\.title), ["reading"])
        XCTAssertEqual(LibraryQuery(filter: .finished).apply(to: comics).map(\.title), ["done"])
        XCTAssertEqual(LibraryQuery(filter: .all).apply(to: comics).count, 3)
    }

    func testSearchMatchesTitleSeriesAndCreators() {
        let comics = [
            comic("file-1", metadata: ComicMetadata(series: "Starfall", number: "1")),
            comic("Midnight Ramen"),
            comic("file-2", metadata: ComicMetadata(writer: "Rumi Tanaka")),
        ]
        XCTAssertEqual(LibraryQuery(search: "star").apply(to: comics).map(\.title), ["file-1"])
        XCTAssertEqual(LibraryQuery(search: "ramen").apply(to: comics).map(\.title), ["Midnight Ramen"])
        XCTAssertEqual(LibraryQuery(search: "tanaka").apply(to: comics).map(\.title), ["file-2"])
    }

    func testSortRecentlyReadPutsOpenedFirst() {
        let comics = [
            comic("never-old", added: 1),
            comic("opened-earlier", opened: 100),
            comic("never-new", added: 50),
            comic("opened-latest", opened: 200),
        ]
        XCTAssertEqual(LibraryQuery(sort: .recentlyRead).apply(to: comics).map(\.title),
                       ["opened-latest", "opened-earlier", "never-new", "never-old"])
    }

    func testSortByTitleUsesNaturalOrderOfDisplayTitle() {
        let comics = [
            comic("x", metadata: ComicMetadata(series: "Starfall", number: "10")),
            comic("y", metadata: ComicMetadata(series: "Starfall", number: "2")),
            comic("Akira"),
        ]
        XCTAssertEqual(LibraryQuery(sort: .title).apply(to: comics).map(\.displayTitle),
                       ["Akira", "Starfall #2", "Starfall #10"])
    }

    func testNextIssueIsLowestLaterNumberInSameSeries() {
        let one = comic("s1", metadata: ComicMetadata(series: "Starfall", number: "1"))
        let three = comic("s3", metadata: ComicMetadata(series: "Starfall", number: "3"))
        let two = comic("s2", metadata: ComicMetadata(series: "Starfall", number: "2"))
        let other = comic("o2", metadata: ComicMetadata(series: "Moonlit", number: "2"))
        let library = [three, other, one, two]
        XCTAssertEqual(LibraryQuery.nextIssue(after: one, in: library)?.title, "s2")
        XCTAssertEqual(LibraryQuery.nextIssue(after: two, in: library)?.title, "s3")
        XCTAssertNil(LibraryQuery.nextIssue(after: three, in: library))
        XCTAssertNil(LibraryQuery.nextIssue(after: comic("loose"), in: library))
    }

    func testContinueReadingIsInProgressByLastOpened() {
        let comics = [
            comic("a", page: 2, opened: 10),
            comic("b"),
            comic("c", page: 5, opened: 30),
            comic("d", finished: true, opened: 40),
        ]
        XCTAssertEqual(LibraryQuery.continueReading(comics).map(\.title), ["c", "a"])
    }
}

final class ComicBookCodingTests: XCTestCase {
    func testDecodesLibrariesSavedBeforeNewFields() throws {
        let json = """
        [{"id":"8B1E6C1A-6D2B-4E47-9C39-2B7C3E7D8A11","title":"Old","fileName":"old.cbz",
          "pageCount":20,"currentPage":4,"dateAdded":700000000}]
        """
        let comics = try JSONDecoder().decode([ComicBook].self, from: Data(json.utf8))
        XCTAssertEqual(comics.first?.title, "Old")
        XCTAssertEqual(comics.first?.isFinished, false)
        XCTAssertNil(comics.first?.lastOpened)
        XCTAssertNil(comics.first?.metadata)
        XCTAssertEqual(comics.first?.bookmarks, [])
        XCTAssertNil(comics.first?.readingMode)
        XCTAssertNil(comics.first?.readsRightToLeft)
        XCTAssertEqual(comics.first?.status, .inProgress)
    }

    func testDisplayTitlePrefersSeries() {
        XCTAssertEqual(ComicBook(title: "f", fileName: "f",
                                 metadata: ComicMetadata(title: "Arc", series: "Starfall", number: "3")).displayTitle,
                       "Starfall #3")
        XCTAssertEqual(ComicBook(title: "f", fileName: "f",
                                 metadata: ComicMetadata(series: "Starfall", volume: 2)).displayTitle,
                       "Starfall Vol. 2")
        XCTAssertEqual(ComicBook(title: "file", fileName: "f").displayTitle, "file")
    }
}
