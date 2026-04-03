import Foundation
import UIKit

@MainActor
final class LibraryManager: ObservableObject {
    static let shared = LibraryManager()

    @Published var comics: [ComicBook] = []
    @Published var isImporting = false
    @Published var importError: String?

    private let storageKey = "philreader.library"
    private let service = CBZService.shared

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

        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "cbz" || ext == "cbr" else {
            importError = "Only .cbz files are supported."
            return
        }

        let destName = UUID().uuidString + ".cbz"
        let destURL = documentsURL.appendingPathComponent(destName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            let count = try await service.pageCount(in: destURL)
            let title = sourceURL.deletingPathExtension().lastPathComponent
            let comic = ComicBook(title: title, fileName: destName, pageCount: count)
            comics.insert(comic, at: 0)
            saveLibrary()
        } catch {
            try? FileManager.default.removeItem(at: destURL)
            importError = error.localizedDescription
        }
    }

    // MARK: - Progress

    func updateProgress(for id: UUID, page: Int) {
        guard let idx = comics.firstIndex(where: { $0.id == id }) else { return }
        comics[idx].currentPage = page
        saveLibrary()
    }

    // MARK: - Delete

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let comic = comics[index]
            try? FileManager.default.removeItem(at: fileURL(for: comic))
            try? FileManager.default.removeItem(at: coverCacheURL(for: comic.id))
        }
        comics.remove(atOffsets: offsets)
        saveLibrary()
    }

    // MARK: - Helpers

    func fileURL(for comic: ComicBook) -> URL {
        documentsURL.appendingPathComponent(comic.fileName)
    }

    func coverImage(for comic: ComicBook) async -> UIImage? {
        let cacheURL = coverCacheURL(for: comic.id)
        if let data = try? Data(contentsOf: cacheURL), let img = UIImage(data: data) { return img }

        guard let data = try? await service.extractCover(from: fileURL(for: comic)),
              let img = UIImage(data: data) else { return nil }

        let size = CGSize(width: 300, height: 450)
        let thumb = UIGraphicsImageRenderer(size: size).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
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
