import Foundation

struct ComicBook: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var fileName: String
    var pageCount: Int
    var currentPage: Int
    var dateAdded: Date
    var lastOpened: Date?
    var isFinished: Bool
    var metadata: ComicMetadata?

    init(id: UUID = UUID(), title: String, fileName: String, pageCount: Int = 0, metadata: ComicMetadata? = nil) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.pageCount = pageCount
        self.currentPage = 0
        self.dateAdded = Date()
        self.lastOpened = nil
        self.isFinished = false
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        fileName = try c.decode(String.self, forKey: .fileName)
        pageCount = try c.decode(Int.self, forKey: .pageCount)
        currentPage = try c.decode(Int.self, forKey: .currentPage)
        dateAdded = try c.decode(Date.self, forKey: .dateAdded)
        // Added after the first release; older libraries don't have them.
        lastOpened = try c.decodeIfPresent(Date.self, forKey: .lastOpened)
        isFinished = try c.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
        metadata = try c.decodeIfPresent(ComicMetadata.self, forKey: .metadata)
    }

    enum ReadStatus {
        case unread, inProgress, finished
    }

    var status: ReadStatus {
        if isFinished { return .finished }
        return currentPage > 0 || lastOpened != nil ? .inProgress : .unread
    }

    var progress: Double {
        if isFinished { return 1 }
        guard pageCount > 1 else { return 0 }
        return Double(currentPage) / Double(pageCount - 1)
    }

    /// "Series #2" when metadata names a series, otherwise the metadata or file title.
    var displayTitle: String {
        if let series = metadata?.series {
            if let number = metadata?.number { return "\(series) #\(number)" }
            if let volume = metadata?.volume { return "\(series) Vol. \(volume)" }
            return series
        }
        return metadata?.title ?? title
    }

    /// Story title shown under the display title when it adds information.
    var subtitle: String? {
        guard metadata?.series != nil, let storyTitle = metadata?.title else { return nil }
        return storyTitle
    }
}
