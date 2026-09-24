import Foundation
import UIKit

@MainActor
final class LibraryManager: ObservableObject {
    static let shared = LibraryManager()

    @Published var comics: [ComicBook] = []
    @Published private(set) var collections: [ComicCollection] = []
    @Published private(set) var linkedFolders: [LinkedFolder] = []
    @Published private(set) var isScanning = false
    @Published var isImporting = false
    @Published var importError: String?

    private let storageKey = "philreader.library"
    private let collectionsKey = "philreader.collections"
    private let foldersKey = "philreader.linkedFolders"
    /// Resolved linked-folder URLs with security-scoped access kept open for the app's lifetime.
    private var folderRoots: [UUID: URL] = [:]

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

    func addReadingTime(_ id: UUID, seconds: TimeInterval) {
        guard seconds > 0 else { return }
        update(id) { $0.readingTime += seconds }
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

    /// Deletes imported comics' files. Comics from a linked folder are only
    /// removed from the library: the user's own file stays where it is, and
    /// rescans skip it.
    func delete(at offsets: IndexSet) {
        for index in offsets {
            let comic = comics[index]
            try? FileManager.default.removeItem(at: coverCacheURL(for: comic.id))
            ExtractedArchive.remove(for: fileURL(for: comic))
            if let folderID = comic.linkedFolderID, let path = comic.relativePath {
                updateFolder(folderID) { $0.excludedPaths.insert(path) }
            } else if !comic.fileName.isEmpty {
                try? FileManager.default.removeItem(at: fileURL(for: comic))
            }
        }
        let removed = Set(offsets.map { comics[$0].id })
        comics.remove(atOffsets: offsets)
        saveLibrary()
        updateCollections { collections in
            for index in collections.indices { collections[index].remove(removed) }
        }
    }

    func delete(_ ids: Set<UUID>) {
        delete(at: IndexSet(comics.indices.filter { ids.contains(comics[$0].id) }))
    }

    func markFinished(_ ids: Set<UUID>) {
        for id in ids { markFinished(id) }
    }

    func markUnread(_ ids: Set<UUID>) {
        for id in ids { markUnread(id) }
    }

    // MARK: - Collections

    @discardableResult
    func createCollection(named name: String, color: CollectionColor, comicIDs: [UUID] = []) -> ComicCollection {
        let collection = ComicCollection(name: name, color: color, comicIDs: comicIDs)
        updateCollections { $0.append(collection) }
        return collection
    }

    func updateCollection(_ id: UUID, _ change: (inout ComicCollection) -> Void) {
        updateCollections { collections in
            guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
            change(&collections[index])
        }
    }

    func deleteCollection(_ id: UUID) {
        updateCollections { $0.removeAll { $0.id == id } }
    }

    func collection(withID id: UUID) -> ComicCollection? {
        collections.first { $0.id == id }
    }

    /// Comics in a collection, in collection order.
    func comics(in collection: ComicCollection) -> [ComicBook] {
        let byID = Dictionary(uniqueKeysWithValues: comics.map { ($0.id, $0) })
        return collection.comicIDs.compactMap { byID[$0] }
    }

    private func updateCollections(_ change: (inout [ComicCollection]) -> Void) {
        change(&collections)
        if let data = try? JSONEncoder().encode(collections) {
            UserDefaults.standard.set(data, forKey: collectionsKey)
        }
    }

    func delete(_ comic: ComicBook) {
        guard let index = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        delete(at: IndexSet(integer: index))
    }

    func comic(withID id: UUID) -> ComicBook? {
        comics.first { $0.id == id }
    }

    #if DEBUG
    private var demoPreparation: Task<Void, Never>?

    /// Imports demo comics from Documents and applies demo reading progress, once.
    func prepareDemoLibrary() async {
        if demoPreparation == nil { demoPreparation = Task { await prepareDemoLibraryOnce() } }
        await demoPreparation?.value
    }

    private func prepareDemoLibraryOnce() async {
        guard DemoLaunch.importsLibrary else { return }
        let ownFiles = Set(comics.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let format = ComicFormat(url: file), !ownFiles.contains(file.lastPathComponent),
                  file.lastPathComponent != DemoLaunch.linkedFolderName else { continue }
            let title = format == .folder ? file.lastPathComponent : file.deletingPathExtension().lastPathComponent
            if !comics.contains(where: { $0.title == title }) { await importComic(from: file) }
        }
        if let name = DemoLaunch.linkedFolderName, !linkedFolders.contains(where: { $0.name == name }) {
            await linkFolder(documentsURL.appendingPathComponent(name, isDirectory: true))
        }
        if DemoLaunch.createsCollections && collections.isEmpty {
            func ids(_ titles: [String]) -> [UUID] {
                titles.compactMap { title in comics.first { $0.title == title }?.id }
            }
            createCollection(named: "Favourites", color: .red, comicIDs: ids(["Starfall 1", "Moonlit 1", "Midnight Ramen 1"]))
            createCollection(named: "Weekend Reads", color: .indigo, comicIDs: ids(["Paper Tigers 1", "Starfall 2"]))
        }
        for (offset, entry) in DemoLaunch.progress.enumerated() {
            guard let comic = comics.first(where: { $0.title == entry.title }) else { continue }
            update(comic.id) { comic in
                comic.currentPage = max(entry.page - 1, 0)
                comic.isFinished = entry.page >= comic.pageCount
                // A few days apart, so Reading Now shows a spread of dates.
                comic.lastOpened = Date().addingTimeInterval(-3600 - 86_400 * 3 * Double(offset))
            }
        }
    }
    #endif

    // MARK: - Helpers

    func fileURL(for comic: ComicBook) -> URL {
        if let folderID = comic.linkedFolderID {
            guard let root = root(for: folderID), let path = comic.relativePath else {
                // The folder can't be reached; point somewhere that simply doesn't exist.
                return FileManager.default.temporaryDirectory.appendingPathComponent("unavailable-\(comic.id.uuidString)")
            }
            return root.appendingPathComponent(path)
        }
        return documentsURL.appendingPathComponent(comic.fileName)
    }

    // MARK: - Linked folders

    /// Links a folder (usually in iCloud Drive) whose comics are read in place and kept in sync.
    func linkFolder(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        guard let bookmark = try? url.bookmarkData() else {
            if accessed { url.stopAccessingSecurityScopedResource() }
            importError = "PhilReader couldn't get lasting access to \u{201C}\(url.lastPathComponent)\u{201D}."
            return
        }
        let folder = LinkedFolder(name: url.lastPathComponent, bookmark: bookmark)
        folderRoots[folder.id] = url
        linkedFolders.append(folder)
        saveFolders()
        await rescan(folder.id)
    }

    /// Stops following a folder and removes its comics from the library (the files stay put).
    func unlinkFolder(_ id: UUID) {
        let ids = Set(comics.filter { $0.linkedFolderID == id }.map(\.id))
        removeFromLibrary(ids)
        folderRoots.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        linkedFolders.removeAll { $0.id == id }
        saveFolders()
    }

    func rescanLinkedFolders() async {
        for folder in linkedFolders { await rescan(folder.id) }
    }

    /// Adds new comics, drops ones whose files are gone, and fills in details
    /// for comics that are on this device.
    func rescan(_ id: UUID) async {
        guard let root = root(for: id), let folder = linkedFolders.first(where: { $0.id == id }) else { return }
        isScanning = true
        defer { isScanning = false }

        let items = await Task.detached(priority: .utility) { FolderScanner.scan(root) }.value
        let present = Set(items.map(\.relativePath))
        let gone = comics.filter { $0.linkedFolderID == id && !present.contains($0.relativePath ?? "") }
        removeFromLibrary(Set(gone.map(\.id)))

        let known = Set(comics.filter { $0.linkedFolderID == id }.compactMap(\.relativePath))
        for item in items where !known.contains(item.relativePath) && !folder.excludedPaths.contains(item.relativePath) {
            let fileName = (item.relativePath as NSString).lastPathComponent
            var comic = ComicBook(title: (fileName as NSString).deletingPathExtension, fileName: "")
            comic.linkedFolderID = id
            comic.relativePath = item.relativePath
            comics.append(comic)
        }
        saveLibrary()
        updateFolder(id) { $0.lastScanned = Date() }

        for comic in comics where comic.linkedFolderID == id && comic.pageCount == 0 {
            if CloudFiles.isDownloaded(fileURL(for: comic)) { await refreshDetails(comic.id) }
        }
    }

    /// Downloads a linked comic from iCloud and reads its page count and metadata.
    func download(_ id: UUID) async {
        guard let comic = comic(withID: id) else { return }
        do {
            try await CloudFiles.ensureDownloaded(fileURL(for: comic))
            await refreshDetails(id)
        } catch {
            importError = "\u{201C}\(comic.title)\u{201D} couldn't be downloaded from iCloud."
        }
    }

    /// Called by the reader once a comic is open, so linked comics learn their page count.
    func didOpen(_ id: UUID, pageCount: Int) {
        guard let comic = comic(withID: id), comic.pageCount != pageCount else { return }
        update(id) { $0.pageCount = pageCount }
        if comic.metadata == nil { Task { await refreshDetails(id) } }
    }

    func comicCount(in folder: LinkedFolder) -> Int {
        comics.filter { $0.linkedFolderID == folder.id }.count
    }

    private func refreshDetails(_ id: UUID) async {
        guard let comic = comic(withID: id) else { return }
        let url = fileURL(for: comic)
        guard let count = try? await Task.detached(priority: .utility, operation: { try ComicSources.open(url).pageCount }).value
        else { return }
        let metadata = await ComicSources.metadata(for: url)
        update(id) { comic in
            comic.pageCount = count
            if let metadata { comic.metadata = metadata }
        }
    }

    /// Removes comics from the library without touching their files.
    private func removeFromLibrary(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for comic in comics where ids.contains(comic.id) {
            try? FileManager.default.removeItem(at: coverCacheURL(for: comic.id))
        }
        comics.removeAll { ids.contains($0.id) }
        saveLibrary()
        updateCollections { collections in
            for index in collections.indices { collections[index].remove(ids) }
        }
    }

    private func root(for id: UUID) -> URL? {
        if let url = folderRoots[id] { return url }
        guard let index = linkedFolders.firstIndex(where: { $0.id == id }) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: linkedFolders[index].bookmark, bookmarkDataIsStale: &stale) else {
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData() {
            linkedFolders[index].bookmark = fresh
            saveFolders()
        }
        folderRoots[id] = url
        return url
    }

    private func updateFolder(_ id: UUID, _ change: (inout LinkedFolder) -> Void) {
        guard let index = linkedFolders.firstIndex(where: { $0.id == id }) else { return }
        change(&linkedFolders[index])
        saveFolders()
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(linkedFolders) {
            UserDefaults.standard.set(data, forKey: foldersKey)
        }
    }

    func coverImage(for comic: ComicBook) async -> UIImage? {
        let cacheURL = coverCacheURL(for: comic.id)
        if let data = try? Data(contentsOf: cacheURL), let img = UIImage(data: data) { return img }

        let url = fileURL(for: comic)
        // Covers never trigger iCloud downloads; they appear once the comic is on this device.
        guard CloudFiles.isDownloaded(url),
              let source = try? await Task.detached(operation: { try ComicSources.open(url) }).value,
              let thumb = await source.image(at: 0, maxPixelSize: 600, maxWidth: nil) else { return nil }

        try? thumb.jpegData(compressionQuality: 0.8)?.write(to: cacheURL)
        return thumb
    }

    // MARK: - Caches

    private var cacheDirectories: [URL] {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return [caches.appendingPathComponent("covers", isDirectory: true), ExtractedArchive.cacheRoot]
    }

    /// Bytes used by cover thumbnails and unpacked CB7/CBR comics.
    func cacheSize() async -> Int64 {
        let directories = cacheDirectories
        return await Task.detached(priority: .utility) {
            directories.reduce(Int64(0)) { total, directory in
                let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
                var size = total
                while let url = files?.nextObject() as? URL {
                    size += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
                }
                return size
            }
        }.value
    }

    /// Clears thumbnails and unpacked archives; both are rebuilt when needed.
    func clearCaches() {
        for directory in cacheDirectories { try? FileManager.default.removeItem(at: directory) }
        objectWillChange.send()
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
        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let saved = try? JSONDecoder().decode([LinkedFolder].self, from: data) {
            linkedFolders = saved
        }
        if let data = UserDefaults.standard.data(forKey: collectionsKey),
           let saved = try? JSONDecoder().decode([ComicCollection].self, from: data) {
            collections = saved
        }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([ComicBook].self, from: data) else { return }
        comics = saved
    }
}
