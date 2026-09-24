import Foundation
import ImageIO
import UIKit
import ZIPFoundation

/// An open CBZ archive that reads and decodes pages on demand, so only the
/// pages being viewed are ever held in memory.
actor CBZDocument {
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

    func image(at index: Int, maxPixelSize: CGFloat) -> UIImage? {
        guard let data = try? pageData(at: index) else { return nil }
        return ImageDownsampler.image(from: data, maxPixelSize: maxPixelSize)
    }
}

enum ImageDownsampler {
    /// Decodes image data at no more than `maxPixelSize` on its longest side.
    /// Decoding straight to the target size avoids ever materialising a
    /// full-resolution bitmap for oversized scans.
    static func image(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
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
