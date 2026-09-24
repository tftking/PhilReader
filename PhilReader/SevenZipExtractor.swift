import Foundation
import SWCompression

/// Unpacks CB7 (7-Zip) comics using SWCompression.
enum SevenZipExtractor {
    static func extract(_ archiveURL: URL, into folder: URL) throws {
        let data = try Data(contentsOf: archiveURL, options: .alwaysMapped)
        for entry in try SevenZipContainer.open(container: data) where entry.info.type == .regular {
            guard let bytes = entry.data else { continue }
            try ExtractedArchive.write(bytes, named: entry.info.name, into: folder)
        }
    }
}
