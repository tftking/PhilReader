// Generates a small manga-style CBZ (with ComicInfo.xml) for trying the reader
// and for CI screenshots.
//
//     swift Scripts/make-sample-cbz.swift "Starfall 1.cbz" \
//         --series Starfall --number 1 --title "First Light" --hue 0.6 --pages 12
//
// Add `--format pdf` or `--format folder` for the other formats PhilReader opens.
//
// Requires macOS (uses AppKit for drawing and /usr/bin/zip for packaging).
import AppKit

var arguments = Array(CommandLine.arguments.dropFirst())
let output = arguments.isEmpty ? "Sample Manga.cbz" : arguments.removeFirst()
var options: [String: String] = [:]
while arguments.count >= 2, arguments[0].hasPrefix("--") {
    options[String(arguments[0].dropFirst(2))] = arguments[1]
    arguments.removeFirst(2)
}
let series = options["series"] ?? "Phil Reader"
let issue = options["number"] ?? "1"
let storyTitle = options["title"] ?? "A Sample Manga"
let hue = CGFloat(Double(options["hue"] ?? "") ?? 0.98)
let pageCount = Int(options["pages"] ?? "") ?? 12
let writer = options["writer"] ?? "PhilReader Studio"
/// "cbz" (default), "pdf" or "folder".
let outputFormat = options["format"] ?? "cbz"
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
    let accent = NSColor(calibratedHue: hue, saturation: 0.72, brightness: 0.88, alpha: 1)
    let deep = NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.16, alpha: 1)
    NSGradient(starting: deep, ending: ink)!.draw(in: CGRect(origin: .zero, size: pageSize), angle: -90)
    accent.setFill()
    NSBezierPath(ovalIn: CGRect(x: 230, y: 560, width: 740, height: 740)).fill()
    screentone(in: CGRect(x: 230, y: 560, width: 740, height: 370), seed: 1)
    let titleSize: CGFloat = series.count > 9 ? 150 : 210
    text(series.uppercased(), size: titleSize, color: paper)
        .draw(with: CGRect(x: 60, y: 1320, width: pageSize.width - 120, height: 420), options: .usesLineFragmentOrigin)
    text("#\(issue)", size: 90, weight: .heavy, color: accent)
        .draw(in: CGRect(x: 0, y: 400, width: pageSize.width, height: 120))
    text(storyTitle, size: 52, weight: .semibold, color: paper.withAlphaComponent(0.85))
        .draw(in: CGRect(x: 0, y: 300, width: pageSize.width, height: 80))
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

let comicInfo = """
<?xml version="1.0" encoding="utf-8"?>
<ComicInfo>
  <Title>\(storyTitle)</Title>
  <Series>\(series)</Series>
  <Number>\(issue)</Number>
  <Summary>A sample comic generated by PhilReader's test tooling, drawn in a manga style with screentone panels and speech bubbles.</Summary>
  <Writer>\(writer)</Writer>
  <Penciller>\(writer)</Penciller>
  <Publisher>PhilReader</Publisher>
  <Year>2026</Year>
  <PageCount>\(pageCount)</PageCount>
  <Manga>YesAndRightToLeft</Manga>
</ComicInfo>
"""
try comicInfo.write(to: workDir.appendingPathComponent("ComicInfo.xml"), atomically: true, encoding: .utf8)
files.append("ComicInfo.xml")

let outputURL = URL(fileURLWithPath: output, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
try? FileManager.default.removeItem(at: outputURL)

switch outputFormat {
case "folder":
    // A plain folder of images plus ComicInfo.xml.
    try FileManager.default.moveItem(at: workDir, to: outputURL)
case "pdf":
    // One PDF page per image, with the JPEG data embedded as-is.
    var mediaBox = CGRect(x: 0, y: 0, width: pageSize.width / 2, height: pageSize.height / 2)
    let info = [kCGPDFContextTitle: "\(series) #\(issue)", kCGPDFContextAuthor: writer] as CFDictionary
    guard let pdf = CGContext(outputURL as CFURL, mediaBox: &mediaBox, info) else { fatalError("Couldn't create PDF") }
    for name in files where name.hasSuffix(".jpg") {
        guard let source = CGImageSourceCreateWithURL(workDir.appendingPathComponent(name) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: mediaBox)
        pdf.endPDFPage()
    }
    pdf.closePDF()
    try? FileManager.default.removeItem(at: workDir)
default:
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = workDir
    zip.arguments = ["-q", "-0", outputURL.path] + files
    try zip.run()
    zip.waitUntilExit()
    try? FileManager.default.removeItem(at: workDir)
    guard zip.terminationStatus == 0 else { fatalError("zip failed with status \(zip.terminationStatus)") }
}
print("Wrote \(pageCount) pages to \(outputURL.path) (\(outputFormat))")
