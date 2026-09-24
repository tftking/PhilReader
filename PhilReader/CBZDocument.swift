import Foundation
import ImageIO
import UIKit
import ZIPFoundation

/// An open CBZ archive that reads and decodes pages on demand, so only the
/// pages being viewed are ever held in memory.
actor CBZDocument: ComicPageSource {
    nonisolated let pageCount: Int
    private let archive: Archive
    private let entries: [Entry]

    init(url: URL) throws {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CBZError.invalidArchive(url)
        }
        self.archive = archive
        self.entries = CBZService.sortedImageEntries(in: archive)
        self.pageCount = entries.count
    }

    func pageData(at index: Int) throws -> Data {
        guard entries.indices.contains(index) else { throw CBZError.pageOutOfRange(index) }
        var buffer = Data()
        _ = try archive.extract(entries[index]) { buffer.append($0) }
        return buffer
    }

    func image(at index: Int, maxPixelSize: CGFloat, maxWidth: CGFloat? = nil) -> UIImage? {
        guard let data = try? pageData(at: index) else { return nil }
        return ImageDownsampler.image(from: data, maxPixelSize: maxPixelSize, maxWidth: maxWidth)
    }
}

enum ImageDownsampler {
    /// Decodes image data at no more than `maxPixelSize` on its longest side.
    /// Decoding straight to the target size avoids ever materialising a
    /// full-resolution bitmap for oversized scans.
    ///
    /// With `maxWidth`, the limit is instead set by width, so tall webtoon
    /// strips stay sharp when shown at full screen width.
    static func image(from data: Data, maxPixelSize: CGFloat, maxWidth: CGFloat? = nil) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        var maxPixelSize = maxPixelSize
        if let maxWidth,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat, width > 0 {
            let scale = min(1, maxWidth / width)
            maxPixelSize = min(max(width, height) * scale, 8000)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

extension UIImage {
    /// Approximate decoded size in bytes, used as the cache cost.
    var memoryCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
