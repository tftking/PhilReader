import Foundation
import Unrar

/// Unpacks CBR (RAR) comics using Unrar.swift.
///
/// UnRAR source code is used under its license: "UnRAR source code may be used
/// in any software to handle RAR archives without limitations free of charge,
/// but cannot be used to develop RAR (WinRAR) compatible archiver and to
/// re-create RAR compression algorithm, which is proprietary."
enum RarExtractor {
    static func extract(_ archiveURL: URL, into folder: URL) throws {
        let archive = try Unrar.Archive(fileURL: archiveURL)
        for entry in try archive.entries() where !entry.directory && !entry.encrypted {
            let name = entry.fileName
            let isPage = ComicFormat.isImage(URL(fileURLWithPath: name))
            guard isPage || name.lowercased().hasSuffix("comicinfo.xml") else { continue }
            try ExtractedArchive.write(try archive.extract(entry), named: name, into: folder)
        }
    }
}
