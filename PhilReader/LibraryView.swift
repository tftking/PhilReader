import SwiftUI
import UniformTypeIdentifiers

enum LibraryRoute: Hashable {
    case collection(UUID)
    case series(String)
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryManager
    @AppStorage("library.sort") private var sort: LibrarySort = .recentlyRead
    @AppStorage("library.filter") private var filter: LibraryFilter = .all
    @AppStorage("library.layout") private var layout: LibraryLayout = .grid
    @AppStorage("library.coverSize") private var coverSize: CoverSize = .medium
    @AppStorage("library.groupSeries") private var groupsSeries = true

    @State private var search = ""
    @State private var path = NavigationPath()
    @State private var showingFilePicker = false
    @State private var readingComic: ComicBook?
    @State private var infoComic: ComicBook?
    @State private var pendingRead: ComicBook?
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var pendingAdd: PendingCollectionAdd?
    @State private var creatingCollection = false
    @State private var confirmDelete = false
    @State private var isDropTargeted = false

    private static let importableTypes: [UTType] =
        ["cbz", "cbr", "cb7", "rar", "7z"].compactMap { UTType(filenameExtension: $0) } + [.zip, .pdf, .folder]

    private var query: LibraryQuery { LibraryQuery(search: search, sort: sort, filter: filter) }
    private var visibleComics: [ComicBook] { query.apply(to: library.comics) }
    private var entries: [LibraryEntry] {
        groupsSeries && search.isEmpty ? LibraryEntry.grouped(visibleComics) : visibleComics.map(LibraryEntry.comic)
    }
    private var continueReading: [ComicBook] { LibraryQuery.continueReading(library.comics) }
    private var isBrowsing: Bool { search.isEmpty && !isSelecting }
    private var showsShelf: Bool { isBrowsing && filter == .all && !continueReading.isEmpty }

    private var actions: ComicActionHandlers {
        ComicActionHandlers(open: open, info: showInfo,
                            addToCollection: { pendingAdd = PendingCollectionAdd(comicIDs: [$0.id]) })
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.comics.isEmpty {
                    emptyLibrary
                } else {
                    content
                }
            }
            .navigationTitle(isSelecting ? "\(selection.count) Selected" : "Library")
            .toolbar { toolbar }
            .overlay { if library.isImporting { ImportingOverlay() } }
            .overlay { if isDropTargeted { DropTargetOverlay() } }
            .dropDestination(for: URL.self) { urls, _ in
                Task { for url in urls { await library.importComic(from: url) } }
                return !urls.isEmpty
            } isTargeted: { isDropTargeted = $0 }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .collection(let id): CollectionView(collectionID: id, actions: actions)
                case .series(let name): SeriesView(name: name, actions: actions)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: Self.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { for url in urls { await library.importComic(from: url) } }
            }
        }
        .alert("Couldn't Import", isPresented: Binding(
            get: { library.importError != nil },
            set: { if !$0 { library.importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.importError ?? "")
        }
        .confirmationDialog("Delete \(selection.count) \(selection.count == 1 ? "Comic" : "Comics")?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                library.delete(selection)
                setSelecting(false)
            }
        } message: {
            Text("They will be removed from this device.")
        }
        .sheet(item: $pendingAdd) { pending in
            AddToCollectionSheet(comicIDs: pending.comicIDs) { setSelecting(false) }
        }
        .sheet(isPresented: $creatingCollection) {
            CollectionEditor(title: "New Collection") { name, color in
                let collection = library.createCollection(named: name, color: color)
                path.append(LibraryRoute.collection(collection.id))
            }
        }
        .sheet(item: $infoComic, onDismiss: openPendingComic) { comic in
            ComicDetailView(comicID: comic.id) { selected in
                pendingRead = selected
                infoComic = nil
            }
        }
        .fullScreenCover(item: $readingComic, onDismiss: openPendingComic) { comic in
            ReaderView(comic: comic, fileURL: library.fileURL(for: comic)) { next in
                pendingRead = next
            }
        }
        #if DEBUG
        .task { await prepareDemo() }
        #endif
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if showsShelf {
                    ContinueReadingShelf(comics: continueReading, actions: actions)
                }

                if isBrowsing && filter == .all {
                    CollectionsShelf(collections: library.collections,
                                     open: { path.append(LibraryRoute.collection($0.id)) },
                                     create: { creatingCollection = true })
                }

                VStack(alignment: .leading, spacing: 16) {
                    FilterBar(selection: $filter, comics: library.comics)

                    if entries.isEmpty {
                        noMatches
                    } else {
                        ComicItemsView(entries: entries, layout: layout, coverSize: coverSize,
                                       isSelecting: isSelecting, selection: $selection, actions: actions,
                                       openSeries: { path.append(LibraryRoute.series($0)) })
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .searchable(text: $search, prompt: "Titles, series, creators")
        .animation(.default, value: filter)
        .animation(.default, value: sort)
        .animation(.default, value: layout)
        .animation(.default, value: groupsSeries)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .navigationBarLeading) {
                let allIDs = Set(visibleComics.map(\.id))
                Button(selection == allIDs ? "Deselect All" : "Select All") {
                    selection = selection == allIDs ? [] : allIDs
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { setSelecting(false) }.bold()
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    Button { library.markFinished(selection); setSelecting(false) } label: {
                        Label("Mark as Read", systemImage: "checkmark.circle")
                    }
                    Button { library.markUnread(selection); setSelecting(false) } label: {
                        Label("Mark as Unread", systemImage: "circle")
                    }
                } label: {
                    Label("Mark", systemImage: "checkmark.circle")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button { pendingAdd = PendingCollectionAdd(comicIDs: Array(selection)) } label: {
                    Label("Add to Collection", systemImage: "folder.badge.plus")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
                .disabled(selection.isEmpty)
            }
        } else {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !library.comics.isEmpty {
                    Menu {
                        viewOptions
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("View Options")
                }
                Button { showingFilePicker = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Import Comics")
            }
        }
    }

    @ViewBuilder
    private var viewOptions: some View {
        Button { setSelecting(true) } label: { Label("Select", systemImage: "checkmark.circle") }
        Divider()
        Picker("Layout", selection: $layout) {
            Label("Grid", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
            Label("List", systemImage: "list.bullet").tag(LibraryLayout.list)
        }
        if layout == .grid {
            Picker("Cover Size", selection: $coverSize) {
                ForEach(CoverSize.allCases) { Text($0.label).tag($0) }
            }
        }
        Toggle(isOn: $groupsSeries) { Label("Group by Series", systemImage: "square.stack") }
        Divider()
        Picker("Sort By", selection: $sort) {
            ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Your Library Is Empty")
                .font(.title2.bold())
            Text("Import comics (.cbz, .cbr, .cb7, .pdf or a folder\nof images) from Files, or open one from another app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showingFilePicker = true } label: {
                Label("Import Comics", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(search.isEmpty ? "Nothing here yet" : "No results for \u{201C}\(search)\u{201D}")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Actions

    private func open(_ comic: ComicBook) {
        if comic.isFinished { library.restart(comic.id) }
        readingComic = library.comic(withID: comic.id) ?? comic
    }

    private func showInfo(_ comic: ComicBook) {
        infoComic = comic
    }

    /// Opens a comic chosen from a sheet or the reader once that has dismissed.
    private func openPendingComic() {
        guard let comic = pendingRead else { return }
        pendingRead = nil
        open(comic)
    }

    private func setSelecting(_ selecting: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting = selecting
            selection = []
        }
    }

    #if DEBUG
    private func prepareDemo() async {
        await library.prepareDemoLibrary()
        if let name = DemoLaunch.collectionName, let collection = library.collections.first(where: { $0.name == name }) {
            path.append(LibraryRoute.collection(collection.id))
        } else if let series = DemoLaunch.seriesName {
            path.append(LibraryRoute.series(series))
        } else if !DemoLaunch.selectedTitles.isEmpty {
            isSelecting = true
            selection = Set(library.comics.filter { DemoLaunch.selectedTitles.contains($0.title) }.map(\.id))
        } else if let title = DemoLaunch.openTitle, let comic = library.comics.first(where: { $0.title == title }) {
            if let mode = DemoLaunch.mode { library.setReadingMode(comic.id, mode) }
            if let page = DemoLaunch.page { library.updateProgress(for: comic.id, page: max(page - 1, 0)) }
            readingComic = library.comic(withID: comic.id)
        } else if let title = DemoLaunch.infoTitle, let comic = library.comics.first(where: { $0.title == title }) {
            infoComic = comic
        }
    }
    #endif
}

// MARK: - Continue Reading

private struct ContinueReadingShelf: View {
    let comics: [ComicBook]
    let actions: ComicActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Reading")
                .font(.title3.bold())
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(comics) { comic in
                        Button { actions.open(comic) } label: { card(comic) }
                            .buttonStyle(CoverButtonStyle())
                            .contextMenu { ComicActions(comic: comic, handlers: actions) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    private func card(_ comic: ComicBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ComicCoverView(comic: comic)
                .frame(width: 132)
            Text(comic.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            ProgressView(value: comic.progress)
                .tint(.accentColor)
            Text("Page \(comic.currentPage + 1) of \(comic.pageCount)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 132)
        .foregroundStyle(.primary)
    }
}

// MARK: - Pieces

private struct FilterBar: View {
    @Binding var selection: LibraryFilter
    let comics: [ComicBook]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { filter in
                    let isSelected = filter == selection
                    Button { selection = filter } label: {
                        HStack(spacing: 5) {
                            Text(filter.label)
                            Text("\(comics.filter(filter.matches).count)")
                                .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                        }
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// Slight press-down scale, like tapping a book on a shelf.
struct CoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ImportingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Importing…").font(.headline)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct DropTargetOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                Label("Drop to Import", systemImage: "square.and.arrow.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(12)
            .allowsHitTesting(false)
    }
}
