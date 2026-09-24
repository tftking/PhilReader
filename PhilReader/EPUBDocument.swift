import Foundation
import UIKit
import ZIPFoundation

/// Fixed-layout comic EPUBs: the pages are the images the spine points to,
/// either directly or through one XHTML/SVG wrapper per page.
actor EPUBDocument: ComicPageSource {
    nonisolated let pageCount: Int
    private let archive: Archive
    private let entries: [Entry]

    init(url: URL) throws {
        guard let archive = Archive(url: url, accessMode: .read) else { throw ComicSourceError.unreadable(url) }
        let book = EPUBParser.parse(archive)
        self.archive = archive
        self.entries = book.imagePaths.compactMap { archive[$0] }
        self.pageCount = entries.count
    }

    func image(at index: Int, maxPixelSize: CGFloat, maxWidth: CGFloat?) -> UIImage? {
        guard entries.indices.contains(index) else { return nil }
        var data = Data()
        guard (try? archive.extract(entries[index], consumer: { data.append($0) })) != nil else { return nil }
        return ImageDownsampler.image(from: data, maxPixelSize: maxPixelSize, maxWidth: maxWidth)
    }

    static func metadata(for url: URL) -> ComicMetadata? {
        guard let archive = Archive(url: url, accessMode: .read) else { return nil }
        let book = EPUBParser.parse(archive)
        let metadata = ComicMetadata(title: book.title, writer: book.creator,
                                     manga: book.rightToLeft ? "YesAndRightToLeft" : nil)
        return metadata == ComicMetadata() ? nil : metadata
    }
}

enum EPUBParser {
    struct Book {
        var imagePaths: [String] = []
        var title: String?
        var creator: String?
        var rightToLeft = false
    }

    static func parse(_ archive: Archive) -> Book {
        var book = Book()
        guard let container = read("META-INF/container.xml", in: archive),
              let opfPath = XMLScan(container).elements.first(where: { $0.name == "rootfile" })?.attributes["full-path"],
              let opfData = read(opfPath, in: archive) else {
            book.imagePaths = fallbackImages(in: archive)
            return book
        }

        let opf = XMLScan(opfData)
        let opfFolder = (opfPath as NSString).deletingLastPathComponent
        var manifest: [String: (href: String, type: String)] = [:]
        var manifestOrder: [String] = []
        var spine: [String] = []
        for element in opf.elements {
            switch element.name {
            case "item":
                if let id = element.attributes["id"], let href = element.attributes["href"] {
                    manifest[id] = (resolve(href, from: opfFolder), element.attributes["media-type"] ?? "")
                    manifestOrder.append(id)
                }
            case "itemref":
                if let idref = element.attributes["idref"], element.attributes["linear"] != "no" { spine.append(idref) }
            case "spine":
                book.rightToLeft = element.attributes["page-progression-direction"] == "rtl"
            case "title":
                if book.title == nil { book.title = element.text }
            case "creator":
                if book.creator == nil { book.creator = element.text }
            default:
                break
            }
        }

        for idref in spine {
            guard let item = manifest[idref] else { continue }
            if item.type.hasPrefix("image/") {
                book.imagePaths.append(item.href)
            } else if let page = read(item.href, in: archive), let image = firstImageReference(in: page) {
                book.imagePaths.append(resolve(image, from: (item.href as NSString).deletingLastPathComponent))
            }
        }
        book.imagePaths = book.imagePaths.filter { archive[$0] != nil }
        if book.imagePaths.isEmpty {
            // No usable spine: fall back to the manifest's images, then to every image in the file.
            book.imagePaths = manifestOrder.compactMap { manifest[$0] }.filter { $0.type.hasPrefix("image/") }.map(\.href)
                .filter { archive[$0] != nil }
            if book.imagePaths.isEmpty { book.imagePaths = fallbackImages(in: archive) }
        }
        return book
    }

    /// The first `<img src>` or SVG `<image href>` in an XHTML page.
    static func firstImageReference(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let patterns = [#"<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#,
                        #"<(?:svg:)?image\b[^>]*?\b(?:xlink:)?href\s*=\s*["']([^"']+)["']"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range])
        }
        return nil
    }

    /// Resolves an EPUB-relative href against a folder: strips #fragments and
    /// ?queries, percent-decodes, and folds `.` and `..` segments.
    static func resolve(_ href: String, from folder: String) -> String {
        var path = href
        if let cut = path.firstIndex(where: { $0 == "#" || $0 == "?" }) { path = String(path[..<cut]) }
        path = path.removingPercentEncoding ?? path
        var parts = path.hasPrefix("/") ? [] : folder.split(separator: "/").map(String.init)
        for part in path.split(separator: "/").map(String.init) {
            switch part {
            case ".", "": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }

    private static func read(_ path: String, in archive: Archive) -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        guard (try? archive.extract(entry, consumer: { data.append($0) })) != nil else { return nil }
        return data
    }

    private static func fallbackImages(in archive: Archive) -> [String] {
        CBZService.sortedImageEntries(in: archive).map(\.path)
    }
}

/// A flat list of XML elements (local names, attributes, text), enough to
/// read EPUB container and package files without a full DOM.
private struct XMLScan {
    struct Element {
        let name: String
        let attributes: [String: String]
        var text: String?
    }

    private(set) var elements: [Element] = []

    init(_ data: Data) {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        elements = delegate.elements
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var elements: [Element] = []
        private var open: [(index: Int, text: String)] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            // "dc:title" → "title", "opf:item" → "item".
            let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
            elements.append(Element(name: name, attributes: attributes, text: nil))
            open.append((elements.count - 1, ""))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !open.isEmpty else { return }
            open[open.count - 1].text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?) {
            guard let last = open.popLast() else { return }
            let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { elements[last.index].text = text }
        }
    }
}
