import Foundation

/// A folder the user picked (typically in iCloud Drive) whose comics are read
/// in place. Access survives relaunches through a bookmark.
struct LinkedFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bookmark: Data
    /// Relative paths the user removed from the library; rescans skip them.
    var excludedPaths: Set<String>
    var lastScanned: Date?

    init(id: UUID = UUID(), name: String, bookmark: Data) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.excludedPaths = []
        self.lastScanned = nil
    }
}

enum FolderScanner {
    /// A comic file found in a linked folder.
    struct Item: Equatable {
        let relativePath: String
        /// `false` while the file only exists in iCloud and hasn't been downloaded.
        let isDownloaded: Bool
    }

    /// Finds comic files (CBZ, CBR, CB7, PDF) anywhere under `root`, including
    /// iCloud placeholders for files that haven't been downloaded yet.
    static func scan(_ root: URL) -> [Item] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        let base = root.resolvingSymlinksInPath().path
        var items: [String: Item] = [:]
        for case let url as URL in enumerator {
            var name = url.lastPathComponent
            var placeholder = false
            // Older iCloud Drive stores not-yet-downloaded files as ".Name.cbz.icloud".
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
                placeholder = true
            } else if name.hasPrefix(".") {
                continue
            }
            let fileURL = url.deletingLastPathComponent().appendingPathComponent(name)
            guard let format = ComicFormat(url: fileURL), format != .folder else { continue }
            // Resolve the (existing) parent folder, since a placeholder's real file may not exist yet.
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
            guard parent.hasPrefix(base) else { continue }
            let folder = String(parent.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let relative = folder.isEmpty ? name : folder + "/" + name
            let downloaded = !placeholder && CloudFiles.isDownloaded(fileURL)
            items[relative] = Item(relativePath: relative, isDownloaded: downloaded || items[relative]?.isDownloaded == true)
        }
        return items.values.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }
}

enum CloudFiles {
    /// Whether a file's contents are on this device. Files outside iCloud always are.
    static func isDownloaded(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return values.ubiquitousItemDownloadingStatus == .current
    }

    /// Downloads an iCloud file if needed and waits until it's available.
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 600) async throws {
        if isDownloaded(url) { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while !isDownloaded(url) {
            try Task.checkCancellation()
            guard Date() < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
    }
}
