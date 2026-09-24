import Foundation

// MARK: - Collections

struct ComicCollection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var color: CollectionColor
    /// Comics in the order they were added.
    var comicIDs: [UUID]
    /// The comic whose cover represents the collection; defaults to the first one.
    var coverComicID: UUID?
    var dateCreated: Date

    init(id: UUID = UUID(), name: String, color: CollectionColor = .blue, comicIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.comicIDs = comicIDs
        self.coverComicID = nil
        self.dateCreated = Date()
    }

    var coverID: UUID? {
        coverComicID.flatMap { comicIDs.contains($0) ? $0 : nil } ?? comicIDs.first
    }

    mutating func add(_ ids: [UUID]) {
        for id in ids where !comicIDs.contains(id) { comicIDs.append(id) }
    }

    mutating func remove(_ ids: Set<UUID>) {
        comicIDs.removeAll { ids.contains($0) }
        if let cover = coverComicID, ids.contains(cover) { coverComicID = nil }
    }
}

enum CollectionColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, indigo, purple, pink, gray

    var id: Self { self }
}

// MARK: - Series

enum SeriesGrouping {
    /// The series a comic belongs to: `ComicInfo.xml` when present, otherwise
    /// the file name with issue numbers, volumes and years stripped
    /// ("Starfall v02 (2024)" → "Starfall").
    static func seriesName(for comic: ComicBook) -> String {
        if let series = comic.metadata?.series { return series }
        return seriesName(fromFileTitle: comic.title)
    }

    static func seriesName(fromFileTitle title: String) -> String {
        var name = title.replacingOccurrences(of: "_", with: " ")
        let patterns = [
            #"\s*[\(\[][^\)\]]*[\)\]]\s*$"#,                                     // (2024), [Group]
            #"[\s\-]*#\s*\d+(\.\d+)?\s*$"#,                                   // #3
            #"[\s\-]+(?:no\.?|issue|ch\.?|chapter|vol\.?|volume|v)\s*\d+(\.\d+)?\s*$"#, // Vol. 2, v02, Ch 5
            #"[\s\-]+\d+(\.\d+)?\s*$"#,                                          // " 01", " - 12"
        ]
        var changed = true
        while changed {
            changed = false
            for pattern in patterns {
                if let range = name.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                   range.lowerBound != name.startIndex {
                    name.removeSubrange(range)
                    changed = true
                }
            }
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    /// Issues of a series in reading order: by issue/volume number, then title.
    static func ordered(_ comics: [ComicBook]) -> [ComicBook] {
        comics.sorted { a, b in
            switch (a.issueOrder, b.issueOrder) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
    }
}

/// One item in the library grid: a single comic or a stack of issues from one series.
enum LibraryEntry: Identifiable, Equatable {
    case comic(ComicBook)
    case series(name: String, comics: [ComicBook])

    var id: String {
        switch self {
        case .comic(let comic): return comic.id.uuidString
        case .series(let name, _): return "series:" + name.lowercased()
        }
    }

    /// Groups comics that share a series into stacks, keeping the incoming
    /// order (each stack sits where its first issue would have been).
    static func grouped(_ comics: [ComicBook]) -> [LibraryEntry] {
        var buckets: [String: [ComicBook]] = [:]
        var order: [String] = []
        for comic in comics {
            let key = SeriesGrouping.seriesName(for: comic).lowercased()
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(comic)
        }
        return order.map { key in
            let issues = buckets[key] ?? []
            if issues.count == 1 { return .comic(issues[0]) }
            return .series(name: SeriesGrouping.seriesName(for: issues[0]), comics: SeriesGrouping.ordered(issues))
        }
    }
}

// MARK: - Layout preferences

enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list
    var id: Self { self }
}

enum CoverSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }

    var label: String { rawValue.capitalized }

    var minimumWidth: CGFloat {
        switch self {
        case .small: return 84
        case .medium: return 104
        case .large: return 148
        }
    }
}
