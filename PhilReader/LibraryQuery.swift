import Foundation

enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyRead, recentlyAdded, title

    var id: Self { self }

    var label: String {
        switch self {
        case .recentlyRead: return "Recently Read"
        case .recentlyAdded: return "Recently Added"
        case .title: return "Title"
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, unread, inProgress, finished

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .inProgress: return "Reading"
        case .finished: return "Finished"
        }
    }

    func matches(_ comic: ComicBook) -> Bool {
        switch self {
        case .all: return true
        case .unread: return comic.status == .unread
        case .inProgress: return comic.status == .inProgress
        case .finished: return comic.status == .finished
        }
    }
}

struct LibraryQuery {
    var search = ""
    var sort: LibrarySort = .recentlyRead
    var filter: LibraryFilter = .all

    func apply(to comics: [ComicBook]) -> [ComicBook] {
        let term = search.trimmingCharacters(in: .whitespaces)
        return comics
            .filter { filter.matches($0) && (term.isEmpty || Self.comic($0, matches: term)) }
            .sorted(by: areInIncreasingOrder)
    }

    /// In-progress comics, most recently opened first.
    static func continueReading(_ comics: [ComicBook], limit: Int = 10) -> [ComicBook] {
        Array(
            comics
                .filter { $0.status == .inProgress }
                .sorted { ($0.lastOpened ?? $0.dateAdded) > ($1.lastOpened ?? $1.dateAdded) }
                .prefix(limit)
        )
    }

    /// The next issue of the same series in the library, by issue or volume number.
    static func nextIssue(after comic: ComicBook, in comics: [ComicBook]) -> ComicBook? {
        guard let series = comic.metadata?.series, let current = comic.issueOrder else { return nil }
        return comics
            .filter { $0.id != comic.id && $0.metadata?.series == series && ($0.issueOrder ?? -.infinity) > current }
            .min { ($0.issueOrder ?? 0) < ($1.issueOrder ?? 0) }
    }

    private static func comic(_ comic: ComicBook, matches term: String) -> Bool {
        let fields = [comic.displayTitle, comic.title, comic.metadata?.title, comic.metadata?.series,
                      comic.metadata?.writer, comic.metadata?.artist, comic.metadata?.publisher]
        return fields.contains { $0?.localizedStandardContains(term) == true }
    }

    private func areInIncreasingOrder(_ a: ComicBook, _ b: ComicBook) -> Bool {
        switch sort {
        case .recentlyRead:
            // Opened comics first (newest first), then never-opened by date added.
            switch (a.lastOpened, b.lastOpened) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.dateAdded > b.dateAdded
            }
        case .recentlyAdded:
            return a.dateAdded > b.dateAdded
        case .title:
            return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
        }
    }
}
