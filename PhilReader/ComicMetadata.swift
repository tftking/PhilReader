import Foundation

/// Metadata from a `ComicInfo.xml` file (the ComicRack format used by most
/// comic and manga tools).
struct ComicMetadata: Codable, Equatable {
    var title: String?
    var series: String?
    var number: String?
    var volume: Int?
    var summary: String?
    var writer: String?
    var artist: String?
    var publisher: String?
    var year: Int?
    /// Raw `Manga` value: "Yes", "YesAndRightToLeft" or "No".
    var manga: String?

    /// `true` when the file says to read right to left, `false` when it says it
    /// isn't manga, `nil` when it doesn't say.
    var readsRightToLeft: Bool? {
        switch manga?.lowercased() {
        case "yesandrighttoleft": return true
        case "no": return false
        default: return nil
        }
    }

    var hasCreators: Bool { writer != nil || artist != nil || publisher != nil }
}

enum ComicInfoParser {
    static func parse(_ data: Data) -> ComicMetadata? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.values.isEmpty else { return nil }

        func text(_ key: String) -> String? {
            guard let value = delegate.values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }

        let metadata = ComicMetadata(
            title: text("Title"),
            series: text("Series"),
            number: text("Number"),
            volume: text("Volume").flatMap(Int.init),
            summary: text("Summary"),
            writer: text("Writer"),
            artist: text("Penciller") ?? text("Artist"),
            publisher: text("Publisher"),
            year: text("Year").flatMap(Int.init),
            manga: text("Manga")
        )
        return metadata == ComicMetadata() ? nil : metadata
    }

    /// Collects the text of each direct child of the root `<ComicInfo>` element.
    private final class Delegate: NSObject, XMLParserDelegate {
        var values: [String: String] = [:]
        private var depth = 0
        private var current: String?
        private var buffer = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            depth += 1
            if depth == 2 {
                current = elementName
                buffer = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if depth == 2 { buffer += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if depth == 2, let current { values[current] = buffer }
            depth -= 1
        }
    }
}
