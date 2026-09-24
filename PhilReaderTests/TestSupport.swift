import UIKit
import XCTest

/// Builds small ZIP files (stored, no compression) for archive-based tests.
enum TestZip {
    static func data(_ entries: [(String, Data)]) -> Data {
        var body = Data()
        var central = Data()
        for (name, content) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(content)
            let offset = UInt32(body.count)

            body.append(le32(0x04034b50))
            body.append(le16(20)); body.append(le16(0)); body.append(le16(0))
            body.append(le16(0)); body.append(le16(0x21))
            body.append(le32(crc)); body.append(le32(UInt32(content.count))); body.append(le32(UInt32(content.count)))
            body.append(le16(UInt16(nameData.count))); body.append(le16(0))
            body.append(nameData); body.append(content)

            central.append(le32(0x02014b50))
            central.append(le16(20)); central.append(le16(20)); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(crc)); central.append(le32(UInt32(content.count))); central.append(le32(UInt32(content.count)))
            central.append(le16(UInt16(nameData.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0o100644 << 16))
            central.append(le32(offset)); central.append(nameData)
        }
        var end = Data()
        end.append(le32(0x06054b50)); end.append(le16(0)); end.append(le16(0))
        end.append(le16(UInt16(entries.count))); end.append(le16(UInt16(entries.count)))
        end.append(le32(UInt32(central.count))); end.append(le32(UInt32(body.count))); end.append(le16(0))
        return body + central + end
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }
}

enum TestImages {
    /// A solid PNG of the given pixel size.
    static func png(width: Int, height: Int = 40, color: UIColor = .blue) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A 600×900 comic page: `background` paper with black-bordered panels at the given rects.
    static func page(panels: [CGRect], background: UIColor = .white, border: UIColor = .black) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            for panel in panels {
                UIColor(white: 0.6, alpha: 1).setFill()
                context.fill(panel)
                border.setStroke()
                let path = UIBezierPath(rect: panel.insetBy(dx: 3, dy: 3))
                path.lineWidth = 6
                path.stroke()
            }
        }.cgImage!
    }
}
