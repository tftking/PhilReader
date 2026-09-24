// Generates a small manga-style CBZ for trying the reader and for CI screenshots.
//
//     swift Scripts/make-sample-cbz.swift "Sample Manga.cbz"
//
// Requires macOS (uses AppKit for drawing and /usr/bin/zip for packaging).
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Sample Manga.cbz"
let pageCount = 12
let pageSize = CGSize(width: 1200, height: 1800)
let ink = NSColor(white: 0.08, alpha: 1)
let paper = NSColor(white: 0.97, alpha: 1)

let workDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("sample-cbz-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .black, color: NSColor = ink) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    return NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
    ])
}

/// Halftone dots that fade across the panel, like manga screentone.
func screentone(in rect: CGRect, seed: Int) {
    let spacing: CGFloat = 16
    var y = rect.minY + spacing / 2
    while y < rect.maxY {
        var x = rect.minX + spacing / 2
        while x < rect.maxX {
            let t = (x - rect.minX) / rect.width * 0.6 + (y - rect.minY) / rect.height * 0.4
            let shade = seed % 2 == 0 ? t : 1 - t
            let radius = spacing * 0.45 * shade
            if radius > 0.8 {
                ink.withAlphaComponent(0.55).setFill()
                NSBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
            }
            x += spacing
        }
        y += spacing
    }
}

func speechBubble(_ string: String, center: CGPoint, width: CGFloat) {
    let rect = CGRect(x: center.x - width / 2, y: center.y - width * 0.3, width: width, height: width * 0.6)
    let bubble = NSBezierPath(ovalIn: rect)
    paper.setFill(); bubble.fill()
    ink.setStroke(); bubble.lineWidth = 5; bubble.stroke()
    let label = text(string, size: width * 0.11, weight: .heavy)
    let bounds = label.boundingRect(with: CGSize(width: width * 0.75, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin)
    label.draw(with: CGRect(x: center.x - width * 0.375, y: center.y - bounds.height / 2, width: width * 0.75, height: bounds.height),
               options: .usesLineFragmentOrigin)
}

func drawCover() {
    ink.setFill(); CGRect(origin: .zero, size: pageSize).fill()
    NSColor(calibratedRed: 0.86, green: 0.18, blue: 0.24, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: 250, y: 620, width: 700, height: 700)).fill()
    text("PHIL", size: 230, color: paper).draw(in: CGRect(x: 0, y: 1250, width: pageSize.width, height: 300))
    text("READER", size: 150, color: paper).draw(in: CGRect(x: 0, y: 1080, width: pageSize.width, height: 200))
    text("VOL. 1", size: 70, weight: .bold, color: paper).draw(in: CGRect(x: 0, y: 380, width: pageSize.width, height: 100))
    text("A sample manga for testing", size: 40, weight: .medium, color: paper.withAlphaComponent(0.7))
        .draw(in: CGRect(x: 0, y: 300, width: pageSize.width, height: 60))
}

/// Rows of panels; each entry is (relative height, number of panels in that row).
let layouts: [[(CGFloat, Int)]] = [
    [(1, 1), (1.2, 2), (1, 1)],
    [(1.4, 2), (1, 1)],
    [(1, 2), (1, 1), (1, 2)],
]
let lines = ["Where did I put that volume?", "Swipe right for the next page!", "Tap the middle for controls.",
             "Pinch to zoom in close.", "Wait… it's reading right to left?", "That's how manga works!"]

func drawStoryPage(_ number: Int) {
    paper.setFill(); CGRect(origin: .zero, size: pageSize).fill()
    let margin: CGFloat = 70, gutter: CGFloat = 26
    let rows = layouts[number % layouts.count]
    let usable = pageSize.height - margin * 2 - gutter * CGFloat(rows.count - 1)
    let total = rows.reduce(0) { $0 + $1.0 }
    var top = pageSize.height - margin
    var panel = 0
    for (weight, columns) in rows {
        let height = usable * weight / total
        let width = (pageSize.width - margin * 2 - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        for column in 0..<columns {
            // Right-to-left panel order, as in manga.
            let x = pageSize.width - margin - CGFloat(column + 1) * width - CGFloat(column) * gutter
            let rect = CGRect(x: x, y: top - height, width: width, height: height)
            screentone(in: rect.insetBy(dx: 4, dy: 4), seed: number + panel)
            if panel == 0 {
                speechBubble(lines[(number + panel) % lines.count], center: CGPoint(x: rect.midX, y: rect.midY), width: min(rect.width * 0.8, 560))
            }
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 8
            ink.setStroke(); border.stroke()
            panel += 1
        }
        top -= height + gutter
    }
    text("\(number)", size: 34, weight: .bold).draw(in: CGRect(x: 0, y: 12, width: pageSize.width, height: 50))
}

var files: [String] = []
for number in 1...pageCount {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pageSize.width), pixelsHigh: Int(pageSize.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if number == 1 { drawCover() } else { drawStoryPage(number) }
    NSGraphicsContext.restoreGraphicsState()

    // Unpadded names exercise the reader's natural sort (page-2 before page-10).
    let name = "page-\(number).jpg"
    try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!
        .write(to: workDir.appendingPathComponent(name))
    files.append(name)
}

let outputURL = URL(fileURLWithPath: output, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
try? FileManager.default.removeItem(at: outputURL)
let zip = Process()
zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
zip.currentDirectoryURL = workDir
zip.arguments = ["-q", "-0", outputURL.path] + files
try zip.run()
zip.waitUntilExit()
try? FileManager.default.removeItem(at: workDir)
guard zip.terminationStatus == 0 else { fatalError("zip failed with status \(zip.terminationStatus)") }
print("Wrote \(pageCount) pages to \(outputURL.path)")
