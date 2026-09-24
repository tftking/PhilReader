import Foundation
import ZIPFoundation

actor CBZService {
    static let shared = CBZService()

    func extractCover(from url: URL) throws -> Data? {
        guard let archive = Archive(url: url, accessMode: .read),
              let entry = Self.sortedImageEntries(in: archive).first else { return nil }
        var buffer = Data()
        _ = try archive.extract(entry) { buffer.append($0) }
        return buffer.isEmpty ? nil : buffer
    }

    func pageCount(in url: URL) throws -> Int {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CBZError.invalidArchive(url)
        }
        return Self.sortedImageEntries(in: archive).count
    }

    /// Parsed `ComicInfo.xml`, if the archive has one.
    func metadata(in url: URL) -> ComicMetadata? {
        guard let archive = Archive(url: url, accessMode: .read),
              let entry = archive.first(where: {
                  $0.type == .file && ($0.path as NSString).lastPathComponent.lowercased() == "comicinfo.xml"
              }) else { return nil }
        var buffer = Data()
        guard (try? archive.extract(entry, consumer: { buffer.append($0) })) != nil else { return nil }
        return ComicInfoParser.parse(buffer)
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff"]

    /// Image entries in reading order: natural filename sort, skipping macOS metadata.
    static func sortedImageEntries(in archive: Archive) -> [Entry] {
        archive.filter { entry in
            guard entry.type == .file else { return false }
            guard !entry.path.hasPrefix("__MACOSX") else { return false }
            let e = (entry.path as NSString).pathExtension.lowercased()
            return imageExtensions.contains(e)
        }
        .sorted { $0.path.compare($1.path, options: [.numeric, .caseInsensitive]) == .orderedAscending }
    }
}

enum CBZError: LocalizedError {
    case invalidArchive(URL)
    case pageOutOfRange(Int)

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let url): return "Could not open archive: \(url.lastPathComponent)"
        case .pageOutOfRange(let index): return "Page \(index + 1) does not exist."
        }
    }
}
