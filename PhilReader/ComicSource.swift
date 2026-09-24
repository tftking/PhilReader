import Foundation
import PDFKit
import UIKit

/// Anything the reader can page through: a CBZ archive, a PDF or a folder of images.
protocol ComicPageSource: AnyObject, Sendable {
    var pageCount: Int { get }
    /// Decodes a page at no more than `maxPixelSize` on its longest side, or,
    /// with `maxWidth`, at no more than that width.
    func image(at index: Int, maxPixelSize: CGFloat, maxWidth: CGFloat?) async -> UIImage?
}

enum ComicFormat: Equatable {
    case cbz, cb7, cbr, pdf, folder

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "heic", "avif"]

    init?(url: URL) {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true || url.hasDirectoryPath {
            self = .folder
            return
        }
        switch url.pathExtension.lowercased() {
        case "cbz", "zip": self = .cbz
        case "cb7", "7z": self = .cb7
        case "cbr", "rar": self = .cbr
        case "pdf": self = .pdf
        default: return nil
        }
    }

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// File extension used when storing an imported comic; folders have none.
    var storedExtension: String? {
        switch self {
        case .cbz: return "cbz"
        case .cb7: return "cb7"
        case .cbr: return "cbr"
        case .pdf: return "pdf"
        case .folder: return nil
        }
    }

    /// Unpacks solid archive formats into a cached folder; `nil` for formats read in place.
    func extractedFolder(for url: URL) throws -> URL? {
        switch self {
        case .cb7: return try ExtractedArchive.folder(for: url) { try SevenZipExtractor.extract(url, into: $0) }
        case .cbr: return try ExtractedArchive.folder(for: url) { try RarExtractor.extract(url, into: $0) }
        case .cbz, .pdf, .folder: return nil
        }
    }
}

enum ComicSourceError: LocalizedError {
    case unsupported(URL)
    case unreadable(URL)
    case locked(URL)
    case noPages(URL)

    var errorDescription: String? {
        switch self {
        case .unsupported(let url):
            return "\u{201C}\(url.lastPathComponent)\u{201D} isn't a supported format. PhilReader opens .cbz, .cbr, .cb7 and .pdf files and folders of images."
        case .unreadable(let url):
            return "\u{201C}\(url.lastPathComponent)\u{201D} couldn't be read."
        case .locked(let url):
            return "\u{201C}\(url.lastPathComponent)\u{201D} is password protected."
        case .noPages(let url):
            return "\u{201C}\(url.lastPathComponent)\u{201D} doesn't contain any pages."
        }
    }
}

enum ComicSources {
    static func open(_ url: URL) throws -> ComicPageSource {
        switch ComicFormat(url: url) {
        case .cbz: return try CBZDocument(url: url)
        case .cb7, .cbr:
            do {
                guard let folder = try ComicFormat(url: url)?.extractedFolder(for: url) else { throw ComicSourceError.unreadable(url) }
                return try FolderComicDocument(url: folder)
            } catch let error as ComicSourceError {
                throw error
            } catch {
                throw ComicSourceError.unreadable(url)
            }
        case .pdf: return try PDFComicDocument(url: url)
        case .folder: return try FolderComicDocument(url: url)
        case nil: throw ComicSourceError.unsupported(url)
        }
    }

    static func metadata(for url: URL) async -> ComicMetadata? {
        switch ComicFormat(url: url) {
        case .cbz:
            return await CBZService.shared.metadata(in: url)
        case .cb7, .cbr:
            guard let folder = try? ComicFormat(url: url)?.extractedFolder(for: url) else { return nil }
            return await metadata(for: folder)
        case .folder:
            let info = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
                .first { $0.lastPathComponent.lowercased() == "comicinfo.xml" }
            return info.flatMap { try? Data(contentsOf: $0) }.flatMap(ComicInfoParser.parse)
        case .pdf:
            guard let attributes = PDFDocument(url: url)?.documentAttributes else { return nil }
            func text(_ key: PDFDocumentAttribute) -> String? {
                (attributes[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            let metadata = ComicMetadata(title: text(.titleAttribute), summary: text(.subjectAttribute),
                                         writer: text(.authorAttribute))
            return metadata == ComicMetadata() ? nil : metadata
        case nil:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - PDF

/// Renders PDF pages on demand. PDFs are vectors, so pages are rendered at
/// the requested size (never smaller) and stay sharp.
actor PDFComicDocument: ComicPageSource {
    nonisolated let pageCount: Int
    private let document: PDFDocument

    init(url: URL) throws {
        guard let document = PDFDocument(url: url) else { throw ComicSourceError.unreadable(url) }
        guard !document.isLocked else { throw ComicSourceError.locked(url) }
        self.document = document
        self.pageCount = document.pageCount
    }

    func image(at index: Int, maxPixelSize: CGFloat, maxWidth: CGFloat?) -> UIImage? {
        guard let page = document.page(at: index) else { return nil }
        return Self.render(page, maxPixelSize: maxPixelSize, maxWidth: maxWidth)
    }

    static func render(_ page: PDFPage, maxPixelSize: CGFloat, maxWidth: CGFloat?) -> UIImage? {
        let box = page.bounds(for: .mediaBox)
        let quarterTurns = ((page.rotation % 360) + 360) % 360 / 90
        let pageSize = quarterTurns % 2 == 1 ? CGSize(width: box.height, height: box.width) : box.size
        guard pageSize.width > 0, pageSize.height > 0 else { return nil }

        var scale = maxWidth.map { $0 / pageSize.width } ?? maxPixelSize / max(pageSize.width, pageSize.height)
        scale = min(scale, 8000 / max(pageSize.width, pageSize.height))
        let size = CGSize(width: (pageSize.width * scale).rounded(), height: (pageSize.height * scale).rounded())

        if quarterTurns != 0 {
            // PDFKit applies the page's rotation when making thumbnails.
            return page.thumbnail(of: size, for: .mediaBox)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -box.minX, y: -box.minY)
            page.draw(with: .mediaBox, to: cg)
        }
    }
}

// MARK: - Folder

/// A folder of image files, read in natural filename order (including subfolders).
actor FolderComicDocument: ComicPageSource {
    nonisolated let pageCount: Int
    private let files: [URL]

    init(url: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { throw ComicSourceError.unreadable(url) }
        let base = url.standardizedFileURL.path
        files = enumerator
            .compactMap { $0 as? URL }
            .filter { ComicFormat.isImage($0) && !$0.path.contains("/__MACOSX/") }
            .sorted {
                let a = String($0.standardizedFileURL.path.dropFirst(base.count))
                let b = String($1.standardizedFileURL.path.dropFirst(base.count))
                return a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedAscending
            }
        pageCount = files.count
    }

    func image(at index: Int, maxPixelSize: CGFloat, maxWidth: CGFloat?) -> UIImage? {
        guard files.indices.contains(index), let data = try? Data(contentsOf: files[index]) else { return nil }
        return ImageDownsampler.image(from: data, maxPixelSize: maxPixelSize, maxWidth: maxWidth)
    }
}
