import CoreGraphics
import Foundation

/// Finds comic panels on a page by recursively splitting it along gutters:
/// full-width or full-height strips of background colour (an "XY-cut").
/// Works for the grid layouts most comics and manga use; pages it can't
/// split cleanly come back as a single panel.
enum PanelDetector {
    /// Panels in reading order as rectangles normalised to 0...1, origin top-left.
    static func panels(in image: CGImage, rightToLeft: Bool) -> [CGRect] {
        guard let raster = Raster(image: image, maxDimension: 420) else { return [] }
        var found: [Region] = []
        split(raster.fullRegion, in: raster, rightToLeft: rightToLeft, depth: 0, into: &found)

        let pageArea = Double(raster.width * raster.height)
        let panels = found.filter {
            Double($0.width) >= Double(raster.width) * 0.08
                && Double($0.height) >= Double(raster.height) * 0.05
                && Double($0.width * $0.height) >= pageArea * 0.015
        }
        // Dozens of "panels" means the page isn't a clean grid (or it's text); don't guess.
        guard !panels.isEmpty, panels.count <= 16 else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
        return panels.map { region in
            CGRect(x: Double(region.x0) / Double(raster.width),
                   y: Double(region.y0) / Double(raster.height),
                   width: Double(region.width) / Double(raster.width),
                   height: Double(region.height) / Double(raster.height))
        }
    }

    struct Region: Equatable {
        var x0, y0, x1, y1: Int  // half-open: x0..<x1, y0..<y1
        var width: Int { x1 - x0 }
        var height: Int { y1 - y0 }
    }

    private static func split(_ region: Region, in raster: Raster, rightToLeft: Bool,
                              depth: Int, into found: inout [Region]) {
        guard let region = raster.trimmed(region) else { return }
        guard depth < 8 else { return found.append(region) }

        // Rows first (top to bottom), then columns (left to right, or right to left for manga).
        if let bands = raster.bands(in: region, horizontal: true), bands.count > 1 {
            for band in bands { split(band, in: raster, rightToLeft: rightToLeft, depth: depth + 1, into: &found) }
        } else if let bands = raster.bands(in: region, horizontal: false), bands.count > 1 {
            for band in rightToLeft ? bands.reversed() : bands {
                split(band, in: raster, rightToLeft: rightToLeft, depth: depth + 1, into: &found)
            }
        } else {
            found.append(region)
        }
    }

    /// A small grayscale copy of the page with a background classifier.
    struct Raster {
        let width: Int
        let height: Int
        private let pixels: [UInt8]
        private let background: Int
        private let tolerance = 42

        init?(image: CGImage, maxDimension: Int) {
            let scale = min(1, Double(maxDimension) / Double(max(image.width, image.height)))
            let w = max(1, Int(Double(image.width) * scale))
            let h = max(1, Int(Double(image.height) * scale))
            var buffer = [UInt8](repeating: 0, count: w * h)
            let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: w, height: h,
                                              bitsPerComponent: 8, bytesPerRow: w,
                                              space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                context.interpolationQuality = .medium
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w
            height = h
            pixels = buffer
            // The page's background is the most common tone around its border.
            var histogram = [Int](repeating: 0, count: 256)
            for x in 0..<width {
                histogram[Int(buffer[x])] += 1
                histogram[Int(buffer[(height - 1) * width + x])] += 1
            }
            for y in 0..<height {
                histogram[Int(buffer[y * width])] += 1
                histogram[Int(buffer[y * width + width - 1])] += 1
            }
            background = histogram.indices.max { histogram[$0] < histogram[$1] } ?? 255
        }

        var fullRegion: Region { Region(x0: 0, y0: 0, x1: width, y1: height) }

        private func isBackground(_ x: Int, _ y: Int) -> Bool {
            abs(Int(pixels[y * width + x]) - background) <= tolerance
        }

        /// Share of foreground pixels along one row or column of a region.
        private func ink(line: Int, in region: Region, horizontal: Bool) -> Double {
            var count = 0
            if horizontal {
                for x in region.x0..<region.x1 where !isBackground(x, line) { count += 1 }
                return Double(count) / Double(region.width)
            } else {
                for y in region.y0..<region.y1 where !isBackground(line, y) { count += 1 }
                return Double(count) / Double(region.height)
            }
        }

        /// Shrinks a region to the bounding box of its content.
        func trimmed(_ region: Region) -> Region? {
            guard region.width > 0, region.height > 0 else { return nil }
            let rows = (region.y0..<region.y1).filter { ink(line: $0, in: region, horizontal: true) > 0.004 }
            let columns = (region.x0..<region.x1).filter { ink(line: $0, in: region, horizontal: false) > 0.004 }
            guard let top = rows.first, let bottom = rows.last,
                  let left = columns.first, let right = columns.last else { return nil }
            return Region(x0: left, y0: top, x1: right + 1, y1: bottom + 1)
        }

        /// Splits a (trimmed) region at its gutters: runs of near-empty rows or
        /// columns at least 0.8% of the page wide. Returns nil when there are none.
        func bands(in region: Region, horizontal: Bool) -> [Region]? {
            let range = horizontal ? region.y0..<region.y1 : region.x0..<region.x1
            let minimumGap = max(2, Int(Double(horizontal ? height : width) * 0.008))
            var bands: [Region] = []
            var start = range.lowerBound
            var gapStart: Int?
            for line in range {
                let isGutter = ink(line: line, in: region, horizontal: horizontal) < 0.015
                if isGutter {
                    if gapStart == nil { gapStart = line }
                } else if let gap = gapStart {
                    if line - gap >= minimumGap && gap > start {
                        bands.append(horizontal ? Region(x0: region.x0, y0: start, x1: region.x1, y1: gap)
                                                : Region(x0: start, y0: region.y0, x1: gap, y1: region.y1))
                        start = line
                    }
                    gapStart = nil
                }
            }
            guard !bands.isEmpty else { return nil }
            bands.append(horizontal ? Region(x0: region.x0, y0: start, x1: region.x1, y1: region.y1)
                                    : Region(x0: start, y0: region.y0, x1: region.x1, y1: region.y1))
            return bands
        }
    }
}
