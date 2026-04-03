import Foundation
import UIKit
import SwiftUI

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

    private init() {
        loadLibrary()
    }

    // MARK: - Import

    func importComic(from sourceURL: URL) async {
        isImporting = true
        importError = nil
        defer { isImporting = false }

        // Security scope for files opened from outside the sandbox
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "cbz" || ext == "cbr" else {
            importError = "Only .cbz files are supported."
            return
        }

        // Copy into Documents
        let destName = UUID().uuidString + ".cbz"
        let destURL = documentsURL.appendingPathComponent(destName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            importError = "Could not copy file: \(error.localizedDescription)"
            return
        }

        // Extract metadata
        do {
            let count = try await service.pageCount(in: destURL)
            let title = sourceURL.deletingPathExtension().lastPathComponent
            var comic = ComicBook(title: title, fileName: destName, pageCount: count)
            comics.insert(comic, at: 0)
            saveLibrary()
        } catch {
            // Clean up if metadata extraction fails
            try? FileManager.default.removeItem(at: destURL)
            importError = error.localizedDescription
        }
    }

    // MARK: - Progress

    func updateProgress(for comicID: UUID, page: Int) {
        guard let idx = comics.firstIndex(where: { $0.id == comicID }) else { return }
        comics[idx].currentPage = page
        saveLibrary()
    }

    // MARK: - Delete

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let comic = comics[index]
            let fileURL = documentsURL.appendingPathComponent(comic.fileName)
            try? FileManager.default.removeItem(at: fileURL)
            // Also remove cached cover
            let coverURL = coverCacheURL(for: comic.id)
            try? FileManager.default.removeItem(at: coverURL)
        }
        comics.remove(atOffsets: offsets)
        saveLibrary()
    }

    // MARK: - File URL

    func fileURL(for comic: ComicBook) -> URL {
        documentsURL.appendingPathComponent(comic.fileName)
    }

    // MARK: - Cover Cache

    func coverImage(for comic: ComicBook) async -> UIImage? {
        let cacheURL = coverCacheURL(for: comic.id)
        // Return cached version
        if let data = try? Data(contentsOf: cacheURL), let img = UIImage(data: data) {
            return img
        }
        // Extract and cache
        let cbzURL = fileURL(for: comic)
        guard let data = try? await service.extractCover(from: cbzURL),
              let img = UIImage(data: data) else { return nil }

        // Cache as JPEG thumbnail
        let size = CGSize(width: 300, height: 450)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        if let jpeg = thumb.jpegData(compressionQuality: 0.8) {
            try? jpeg.write(to: cacheURL)
        }
        return thumb
    }

    private func coverCacheURL(for id: UUID) -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir.appendingPathComponent("\(id.uuidString).jpg")
    }

    // MARK: - Persistence

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
