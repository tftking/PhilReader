import Foundation
import ZipFoundation

actor CBZService {
    static let shared = CBZService()

    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff"]

    func extractAllPages(from url: URL) throws -> [Data] {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CBZError.invalidArchive(url)
        }
        var pages: [Data] = []
        for entry in sortedImageEntries(in: archive) {
            var buffer = Data()
            _ = try archive.extract(entry) { buffer.append($0) }
            if !buffer.isEmpty { pages.append(buffer) }
        }
        return pages
    }

    func extractCover(from url: URL) throws -> Data? {
        guard let archive = Archive(url: url, accessMode: .read),
              let entry = sortedImageEntries(in: archive).first else { return nil }
        var buffer = Data()
        _ = try archive.extract(entry) { buffer.append($0) }
        return buffer.isEmpty ? nil : buffer
    }

    func pageCount(in url: URL) throws -> Int {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CBZError.invalidArchive(url)
        }
        return sortedImageEntries(in: archive).count
    }

    private func sortedImageEntries(in archive: Archive) -> [Entry] {
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

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let url): return "Could not open archive: \(url.lastPathComponent)"
        }
    }
}
