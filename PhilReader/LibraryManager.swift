import Foundation
import UIKit

@MainActor
final class LibraryManager: ObservableObject {
    static let shared = LibraryManager()

    @Published var comics: [ComicBook] = []
    @Published var isImporting = false
    @Published var importError: String?

    private let storageKey = "philreader.library"

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() { loadLibrary() }

    // MARK: - Import

    func importComic(from sourceURL: URL) async {
        isImporting = true
        importError = nil
        defer { isImporting = false }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let format = ComicFormat(url: sourceURL) else {
            importError = ComicSourceError.unsupported(sourceURL).localizedDescription
            return
        }

        // Keep the extension so the format can be recognised later; folders have none.
        let destName = format.storedExtension.map { "\(UUID().uuidString).\($0)" } ?? UUID().uuidString
        let destURL = documentsURL.appendingPathComponent(destName, isDirectory: format == .folder)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            let count = try await Task.detached(priority: .userInitiated) {
                try ComicSources.open(destURL).pageCount
            }.value
            guard count > 0 else { throw ComicSourceError.noPages(sourceURL) }
            let metadata = await ComicSources.metadata(for: destURL)
            let title = format == .folder
                ? sourceURL.lastPathComponent
                : sourceURL.deletingPathExtension().lastPathComponent
            let comic = ComicBook(title: title, fileName: destName, pageCount: count, metadata: metadata)
            comics.insert(comic, at: 0)
            saveLibrary()
        } catch {
            try? FileManager.default.removeItem(at: destURL)
            ExtractedArchive.remove(for: destURL)
            importError = error.localizedDescription
        }
    }

    // MARK: - Progress

    func updateProgress(for id: UUID, page: Int) {
        update(id) { comic in
            let page = min(max(page, 0), max(comic.pageCount - 1, 0))
            guard comic.currentPage != page || (!comic.isFinished && page == comic.pageCount - 1) else { return }
            comic.currentPage = page
            if comic.pageCount > 0 && page >= comic.pageCount - 1 { comic.isFinished = true }
        }
    }

    func markOpened(_ id: UUID) {
        update(id) { $0.lastOpened = Date() }
    }

    func markFinished(_ id: UUID) {
        update(id) { comic in
            comic.isFinished = true
            comic.lastOpened = comic.lastOpened ?? Date()
        }
    }

    func markUnread(_ id: UUID) {
        update(id) { comic in
            comic.isFinished = false
            comic.currentPage = 0
            comic.lastOpened = nil
        }
    }

    /// Reading again from the start keeps the comic's history but clears "finished".
    func restart(_ id: UUID) {
        update(id) { comic in
            comic.isFinished = false
            comic.currentPage = 0
        }
    }

    func toggleBookmark(_ id: UUID, page: Int) {
        update(id) { comic in
            if let index = comic.bookmarks.firstIndex(of: page) {
                comic.bookmarks.remove(at: index)
            } else {
                comic.bookmarks.append(page)
                comic.bookmarks.sort()
            }
        }
    }

    func setReadingMode(_ id: UUID, _ mode: ReadingMode) {
        update(id) { $0.readingMode = mode }
    }

    func setDirection(_ id: UUID, rightToLeft: Bool) {
        update(id) { $0.readsRightToLeft = rightToLeft }
    }

    private func update(_ id: UUID, _ change: (inout ComicBook) -> Void) {
        guard let index = comics.firstIndex(where: { $0.id == id }) else { return }
        change(&comics[index])
        saveLibrary()
    }

    // MARK: - Delete

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let comic = comics[index]
            try? FileManager.default.removeItem(at: fileURL(for: comic))
            try? FileManager.default.removeItem(at: coverCacheURL(for: comic.id))
            ExtractedArchive.remove(for: fileURL(for: comic))
        }
        comics.remove(atOffsets: offsets)
        saveLibrary()
    }

    func delete(_ comic: ComicBook) {
        guard let index = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        delete(at: IndexSet(integer: index))
    }

    func comic(withID id: UUID) -> ComicBook? {
        comics.first { $0.id == id }
    }

    #if DEBUG
    /// Imports demo comics from Documents and applies demo reading progress.
    func prepareDemoLibrary() async {
        guard DemoLaunch.importsLibrary else { return }
        let ownFiles = Set(comics.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let format = ComicFormat(url: file), !ownFiles.contains(file.lastPathComponent) else { continue }
            let title = format == .folder ? file.lastPathComponent : file.deletingPathExtension().lastPathComponent
            if !comics.contains(where: { $0.title == title }) { await importComic(from: file) }
        }
        for (offset, entry) in DemoLaunch.progress.enumerated() {
            guard let comic = comics.first(where: { $0.title == entry.title }) else { continue }
            update(comic.id) { comic in
                comic.currentPage = max(entry.page - 1, 0)
                comic.isFinished = entry.page >= comic.pageCount
                comic.lastOpened = Date().addingTimeInterval(-3600 * Double(offset + 1))
            }
        }
    }
    #endif

    // MARK: - Helpers

    func fileURL(for comic: ComicBook) -> URL {
        documentsURL.appendingPathComponent(comic.fileName)
    }

    func coverImage(for comic: ComicBook) async -> UIImage? {
        let cacheURL = coverCacheURL(for: comic.id)
        if let data = try? Data(contentsOf: cacheURL), let img = UIImage(data: data) { return img }

        let url = fileURL(for: comic)
        guard let source = try? await Task.detached(operation: { try ComicSources.open(url) }).value,
              let thumb = await source.image(at: 0, maxPixelSize: 600, maxWidth: nil) else { return nil }

        try? thumb.jpegData(compressionQuality: 0.8)?.write(to: cacheURL)
        return thumb
    }

    private func coverCacheURL(for id: UUID) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.uuidString).jpg")
    }

    private func saveLibrary() {
        if let data = try? JSONEncoder().encode(comics) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadLibrary() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([ComicBook].self, from: data) else { return }
        comics = saved
    }
}
