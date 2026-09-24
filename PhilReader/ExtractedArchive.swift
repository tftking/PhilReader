import Foundation

/// 7-Zip and RAR comics are usually "solid": pages can't be read one at a time
/// without decompressing everything before them. They are unpacked once into
/// Caches and then read like a folder of images. The OS may purge the cache;
/// it is simply rebuilt on next open.
enum ExtractedArchive {
    private static let lock = NSLock()

    static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("extracted", isDirectory: true)
    }

    /// Imported comics have unique file names, which key the cache.
    static func folderURL(for archiveURL: URL) -> URL {
        cacheRoot.appendingPathComponent(archiveURL.lastPathComponent, isDirectory: true)
    }

    /// Returns the unpacked folder, running `extract` first if needed.
    static func folder(for archiveURL: URL, extract: (URL) throws -> Void) throws -> URL {
        let folder = folderURL(for: archiveURL)
        let marker = folder.appendingPathComponent(".complete")
        lock.lock()
        defer { lock.unlock() }

        if FileManager.default.fileExists(atPath: marker.path) { return folder }
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try extract(folder)
            try Data().write(to: marker)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    static func remove(for archiveURL: URL) {
        try? FileManager.default.removeItem(at: folderURL(for: archiveURL))
    }

    /// Writes one archive entry. Only pages and ComicInfo.xml are kept, and
    /// paths that would escape the folder (`../`) are ignored.
    static func write(_ data: Data, named name: String, into folder: URL) throws {
        let relative = name.replacingOccurrences(of: "\\", with: "/")
        let target = folder.appendingPathComponent(relative).standardizedFileURL
        guard target.path.hasPrefix(folder.standardizedFileURL.path + "/"),
              !relative.hasPrefix("__MACOSX"),
              ComicFormat.isImage(target) || target.lastPathComponent.lowercased() == "comicinfo.xml"
        else { return }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target)
    }
}
