import Foundation
import UIKit
import ZipFoundation

/// Handles reading and extracting .cbz (zip) comic archives.
actor CBZService {
    static let shared = CBZService()

    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif"]

    // MARK: - Page Extraction

    /// Returns sorted image data for every page in the archive.
    func extractAllPages(from url: URL) throws -> [Data] {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CBZError.invalidArchive(url)
        }

        var entries = sortedImageEntries(in: archive)
        var pages: [Data] = []
        pages.reserveCapacity(entries.count)

        for entry in entries {
            var buffer = Data()
            _ = try archive.extract(entry) { chunk in
                buffer.append(chunk)
            }
            if !buffer.isEmpty {
                pages.append(buffer)
            }
        }
        return pages
    }

    /// Returns only the first page (cover), avoiding full extraction.
    func extractCover(from url: URL) throws -> Data? {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CBZError.invalidArchive(url)
        }

        let entries = sortedImageEntries(in: archive)
        guard let first = entries.first else { return nil }

        var buffer = Data()
        _ = try archive.extract(first) { chunk in
            buffer.append(chunk)
        }
        return buffer.isEmpty ? nil : buffer
    }

    /// Returns the total number of image pages without extracting data.
    func pageCount(in url: URL) throws -> Int {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CBZError.invalidArchive(url)
        }
        return sortedImageEntries(in: archive).count
    }

    // MARK: - Helpers

    private func sortedImageEntries(in archive: Archive) -> [Entry] {
        var entries: [Entry] = []
        for entry in archive where entry.type == .file {
            let ext = (entry.path as NSString).pathExtension.lowercased()
            // Skip macOS metadata files
            if ext.isEmpty || entry.path.hasPrefix("__MACOSX") { continue }
            if imageExtensions.contains(ext) {
                entries.append(entry)
            }
        }
        // Natural sort so page-10 comes after page-9
        return entries.sorted { naturalCompare($0.path, $1.path) }
    }

    private func naturalCompare(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }
}

enum CBZError: LocalizedError {
    case invalidArchive(URL)
    case noImagesFound
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let url): return "Could not open archive: \(url.lastPathComponent)"
        case .noImagesFound:           return "No images found in this file."
        case .extractionFailed(let m): return "Extraction failed: \(m)"
        }
    }
}
