import UIKit

/// How a page is scaled to the screen in paged mode.
enum PageFit: String, CaseIterable, Identifiable {
    case screen, width, height

    var id: Self { self }

    var label: String {
        switch self {
        case .screen: return "Screen"
        case .width: return "Width"
        case .height: return "Height"
        }
    }
}

/// How paged mode moves between pages.
enum PageTransition: String, CaseIterable, Identifiable {
    case slide, fade, none

    var id: Self { self }
    var label: String { rawValue.capitalized }
}

/// Zoom limits for continuous vertical scrolling, where the whole strip is
/// scaled (pinch or double-tap) and panned sideways while zoomed.
enum VerticalZoom {
    static let range: ClosedRange<CGFloat> = 1...3
    static let doubleTapScale: CGFloat = 2

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, range.lowerBound), range.upperBound)
    }

    /// Keeps the zoomed strip covering the screen: at 2× a 400pt-wide strip
    /// can move 200pt either way.
    static func clampedPan(_ pan: CGFloat, scale: CGFloat, width: CGFloat) -> CGFloat {
        let limit = max(0, width * (scale - 1) / 2)
        return min(max(pan, -limit), limit)
    }
}

enum SpreadLayout {
    /// Groups pages into two-page spreads like a printed book: the cover and
    /// any wide (already double-page) scans stand alone, everything else pairs up.
    static func spreads(pageCount: Int, isWide: (Int) -> Bool) -> [[Int]] {
        var groups: [[Int]] = []
        var pending: Int?
        for index in 0..<pageCount {
            if index == 0 || isWide(index) {
                if let page = pending { groups.append([page]) }
                pending = nil
                groups.append([index])
            } else if let page = pending {
                groups.append([page, index])
                pending = nil
            } else {
                pending = index
            }
        }
        if let page = pending { groups.append([page]) }
        return groups
    }

    /// Draws two pages side by side at a shared height, capped so the
    /// combined bitmap stays small.
    static func composite(left: UIImage, right: UIImage, maxHeight: CGFloat = 2400) -> UIImage {
        let height = min(max(left.size.height, right.size.height), maxHeight)
        let leftWidth = left.size.width * height / max(left.size.height, 1)
        let rightWidth = right.size.width * height / max(right.size.height, 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: leftWidth + rightWidth, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            left.draw(in: CGRect(x: 0, y: 0, width: leftWidth, height: height))
            right.draw(in: CGRect(x: leftWidth, y: 0, width: rightWidth, height: height))
        }
    }
}
