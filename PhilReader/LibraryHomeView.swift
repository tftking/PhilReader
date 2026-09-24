import SwiftUI

/// The Library tab: collections, libraries and import, as grouped lists like the Files app.
struct LibraryHomeView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var coordinator: ReadingCoordinator
    @State private var path = NavigationPath()
    @State private var importingComics = false
    @State private var pickingFolder = false
    @State private var creatingCollection = false

    private var recentlyAdded: [ComicBook] {
        Array(library.comics.sorted { $0.dateAdded > $1.dateAdded }.prefix(12))
    }
    private var seriesCount: Int {
        Set(library.comics.map { SeriesGrouping.seriesName(for: $0).lowercased() }).count
    }
    private var finishedCount: Int { library.comics.filter { $0.status == .finished }.count }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !recentlyAdded.isEmpty {
                    Section {
                        RecentlyAddedShelf(comics: recentlyAdded, actions: coordinator.actions)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Recently Added")
                    }
                }
                collectionsSection
                librariesSection
                Section("Browse") {
                    NavigationLink(value: LibraryRoute.allSeries) {
                        LibraryRow("Series", systemImage: "square.stack", count: seriesCount)
                    }
                    NavigationLink(value: LibraryRoute.finished) {
                        LibraryRow("Finished", systemImage: "checkmark.circle", count: finishedCount)
                    }
                }
                Section {
                    Button { importingComics = true } label: {
                        LibraryRow("Import from Files", systemImage: "folder")
                    }
                    Button { pickingFolder = true } label: {
                        LibraryRow("Add Library Folder", systemImage: "icloud")
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text("Import copies comics into PhilReader. A library folder, in iCloud Drive or anywhere in Files, is read in place and kept up to date.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { creatingCollection = true } label: { Label("New Collection", systemImage: "folder.badge.plus") }
                        Button { importingComics = true } label: { Label("Import from Files", systemImage: "square.and.arrow.down") }
                        Button { pickingFolder = true } label: { Label("Add Library Folder", systemImage: "icloud") }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
            .refreshable { await library.rescanLinkedFolders() }
            .libraryDestinations(path: $path, actions: coordinator.actions)
            .fileImporter(isPresented: $importingComics, allowedContentTypes: ComicsGridScreen.importableTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { for url in urls { await library.importComic(from: url) } }
                }
            }
            .sheet(isPresented: $creatingCollection) {
                CollectionEditor(title: "New Collection") { name, color in
                    let collection = library.createCollection(named: name, color: color)
                    path.append(LibraryRoute.collection(collection.id))
                }
            }
            #if DEBUG
            .task { await openDemoScreen() }
            #endif
        }
        // A second file importer on the same view would replace the first, so this one sits outside.
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await library.linkFolder(url) }
            }
        }
    }

    private var collectionsSection: some View {
        Section("Collections") {
            ForEach(library.collections) { collection in
                NavigationLink(value: LibraryRoute.collection(collection.id)) {
                    LibraryRow(collection.name, systemImage: "square.stack.3d.up", tint: collection.color.color,
                               count: collection.comicIDs.count)
                }
                .contextMenu {
                    Button(role: .destructive) { library.deleteCollection(collection.id) } label: {
                        Label("Delete Collection", systemImage: "trash")
                    }
                }
            }
            Button { creatingCollection = true } label: {
                LibraryRow("New Collection", systemImage: "plus")
            }
        }
    }

    private var librariesSection: some View {
        Section("Libraries") {
            NavigationLink(value: LibraryRoute.comics(.all)) {
                LibraryRow("All Comics", systemImage: "books.vertical", count: library.comics.count)
            }
            NavigationLink(value: LibraryRoute.comics(.device)) {
                LibraryRow("On My iPhone", systemImage: "iphone", count: library.comics.filter { !$0.isLinked }.count)
            }
            ForEach(library.linkedFolders) { folder in
                NavigationLink(value: LibraryRoute.comics(.folder(folder.id))) {
                    LibraryRow(folder.name, systemImage: "icloud", count: library.comicCount(in: folder))
                }
                .contextMenu {
                    Button { Task { await library.rescan(folder.id) } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) { library.unlinkFolder(folder.id) } label: {
                        Label("Unlink Folder", systemImage: "folder.badge.minus")
                    }
                }
            }
        }
    }

    #if DEBUG
    private func openDemoScreen() async {
        await library.prepareDemoLibrary()
        guard path.isEmpty else { return }
        if let name = DemoLaunch.collectionName,
           let collection = library.collections.first(where: { $0.name == name }) {
            path.append(LibraryRoute.collection(collection.id))
        } else if let series = DemoLaunch.seriesName {
            path.append(LibraryRoute.series(series))
        } else if let scope = DemoLaunch.libraryScope ?? (DemoLaunch.selectedTitles.isEmpty ? nil : "all") {
            switch scope {
            case "all": path.append(LibraryRoute.comics(.all))
            case "device": path.append(LibraryRoute.comics(.device))
            default:
                if let folder = library.linkedFolders.first(where: { $0.name == scope }) {
                    path.append(LibraryRoute.comics(.folder(folder.id)))
                }
            }
        }
    }
    #endif
}

extension View {
    /// The screens a Library or Search navigation stack can push.
    func libraryDestinations(path: Binding<NavigationPath>, actions: ComicActionHandlers) -> some View {
        navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .comics(let scope):
                ComicsGridScreen(scope: scope) { path.wrappedValue.append(LibraryRoute.series($0)) }
            case .collection(let id):
                CollectionView(collectionID: id, actions: actions)
            case .series(let name):
                SeriesView(name: name, actions: actions)
            case .allSeries:
                SeriesListView()
            case .finished:
                FinishedListView(actions: actions)
            }
        }
    }
}

/// A list row with an outlined accent icon and an optional trailing count, like Panels.
struct LibraryRow: View {
    let title: String
    let systemImage: String
    var tint: Color? = nil
    var count: Int? = nil

    init(_ title: String, systemImage: String, tint: Color? = nil, count: Int? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.count = count
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19))
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint))
                .frame(width: 28)
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let count {
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 3)
    }
}

private struct RecentlyAddedShelf: View {
    let comics: [ComicBook]
    let actions: ComicActionHandlers

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(comics) { comic in
                    Button { actions.open(comic) } label: {
                        ComicCoverView(comic: comic, cornerRadius: 6)
                            .frame(width: 92)
                    }
                    .buttonStyle(CoverButtonStyle())
                    .contextMenu { ComicActions(comic: comic, handlers: actions) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Series and finished lists

struct SeriesListView: View {
    @EnvironmentObject private var library: LibraryManager

    private var series: [(name: String, issues: [ComicBook])] {
        var buckets: [String: [ComicBook]] = [:]
        for comic in library.comics {
            buckets[SeriesGrouping.seriesName(for: comic), default: []].append(comic)
        }
        return buckets
            .map { (name: $0.key, issues: SeriesGrouping.ordered($0.value)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List(series, id: \.name) { entry in
            NavigationLink(value: LibraryRoute.series(entry.name)) {
                HStack(spacing: 14) {
                    if let first = entry.issues.first {
                        ComicCoverView(comic: first, cornerRadius: 4).frame(width: 44)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(.headline)
                        let read = entry.issues.filter { $0.status == .finished }.count
                        Text("\(entry.issues.count) \(entry.issues.count == 1 ? "issue" : "issues") · \(read) read")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Series")
    }
}

struct FinishedListView: View {
    let actions: ComicActionHandlers
    @EnvironmentObject private var library: LibraryManager

    private var finished: [ComicBook] {
        library.comics
            .filter { $0.status == .finished }
            .sorted { ($0.lastOpened ?? $0.dateAdded) > ($1.lastOpened ?? $1.dateAdded) }
    }

    var body: some View {
        List(finished) { comic in
            Button { actions.open(comic) } label: {
                ComicRow(comic: comic, detail: comic.lastOpened.map(ComicRow.relative) ?? "Finished",
                         trailing: nil)
            }
            .contextMenu { ComicActions(comic: comic, handlers: actions) }
        }
        .listStyle(.plain)
        .overlay {
            if finished.isEmpty {
                Text("Comics you finish appear here.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Finished")
    }
}
