import SwiftUI
import UniformTypeIdentifiers

enum LibraryRoute: Hashable {
    case series(String)
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var coordinator: ReadingCoordinator
    @AppStorage("library.sort") private var sort: LibrarySort = .recentlyRead
    @AppStorage("library.filter") private var filter: LibraryFilter = .all
    @AppStorage("library.layout") private var layout: LibraryLayout = .grid
    @AppStorage("library.coverSize") private var coverSize: CoverSize = .medium
    @AppStorage("library.groupSeries") private var groupsSeries = true

    @State private var search = ""
    @State private var path = NavigationPath()
    @State private var showingFilePicker = false
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var isDropTargeted = false

    private static let importableTypes: [UTType] =
        ["cbz", "cbr", "cb7", "rar", "7z"].compactMap { UTType(filenameExtension: $0) } + [.zip, .pdf, .epub, .folder]

    private var query: LibraryQuery { LibraryQuery(search: search, sort: sort, filter: filter) }
    private var visibleComics: [ComicBook] { query.apply(to: library.comics) }
    private var entries: [LibraryEntry] {
        groupsSeries && search.isEmpty ? LibraryEntry.grouped(visibleComics) : visibleComics.map(LibraryEntry.comic)
    }
    private var continueReading: [ComicBook] { LibraryQuery.continueReading(library.comics) }
    private var isBrowsing: Bool { search.isEmpty && !isSelecting }
    private var showsShelf: Bool { isBrowsing && filter == .all && !continueReading.isEmpty }
    private var actions: ComicActionHandlers { coordinator.actions }

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
        #if DEBUG
        .task { await prepareDemo() }
        #endif
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if showsShelf, let latest = continueReading.first {
                    JumpBackInCard(comic: latest) { actions.open(latest) }
                        .contextMenu { ComicActions(comic: latest, handlers: actions) }
                        .padding(.horizontal, 20)
                    if continueReading.count > 1 {
                        ContinueReadingShelf(comics: Array(continueReading.dropFirst()), actions: actions)
                    }
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
        .refreshable { await library.rescanLinkedFolders() }
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
                Button { coordinator.addToCollection(Array(selection)) { setSelecting(false) } } label: {
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
                .font(.system(.title2, design: .rounded).bold())
            Text("Import comics (.cbz, .cbr, .cb7, .pdf, .epub or a\nfolder of images) from Files, or open one from another app.")
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

    private func setSelecting(_ selecting: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting = selecting
            selection = []
        }
    }

    #if DEBUG
    private func prepareDemo() async {
        await library.prepareDemoLibrary()
        if DemoLaunch.collectionName != nil || DemoLaunch.tab != nil {
            return
        } else if let series = DemoLaunch.seriesName {
            path.append(LibraryRoute.series(series))
        } else if !DemoLaunch.selectedTitles.isEmpty {
            isSelecting = true
            selection = Set(library.comics.filter { DemoLaunch.selectedTitles.contains($0.title) }.map(\.id))
        } else if let title = DemoLaunch.openTitle, let comic = library.comics.first(where: { $0.title == title }) {
            if let mode = DemoLaunch.mode { library.setReadingMode(comic.id, mode) }
            if let page = DemoLaunch.page { library.updateProgress(for: comic.id, page: max(page - 1, 0)) }
            coordinator.readingComic = library.comic(withID: comic.id)
        } else if let title = DemoLaunch.infoTitle, let comic = library.comics.first(where: { $0.title == title }) {
            coordinator.infoComic = comic
        }
    }
    #endif
}

// MARK: - Continue Reading

/// The most recently read comic, large, over its own blurred cover.
private struct JumpBackInCard: View {
    let comic: ComicBook
    let open: () -> Void

    @EnvironmentObject private var library: LibraryManager
    @State private var backdrop: UIImage?

    var body: some View {
        Button(action: open) {
            HStack(spacing: 18) {
                ComicCoverView(comic: comic, cornerRadius: 8)
                    .frame(width: 100)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
                VStack(alignment: .leading, spacing: 7) {
                    Text("JUMP BACK IN")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(comic.displayTitle)
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("Page \(comic.currentPage + 1) of \(comic.pageCount)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                    ProgressBar(value: comic.progress)
                        .frame(maxWidth: 150)
                        .padding(.vertical, 2)
                    Label("Continue", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Color(white: 0.12)
                    if let backdrop {
                        Image(uiImage: backdrop)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 40)
                            .saturation(1.4)
                            .transition(.opacity)
                    }
                    LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        }
        .buttonStyle(CoverButtonStyle())
        .task(id: comic.id) {
            let image = await library.coverImage(for: comic)
            withAnimation(.easeOut(duration: 0.3)) { backdrop = image }
        }
    }
}

private struct ContinueReadingShelf: View {
    let comics: [ComicBook]
    let actions: ComicActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Also Reading")
                .font(.system(.title3, design: .rounded).bold())
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
                .frame(width: 96)
            Text(comic.displayTitle)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            ProgressView(value: comic.progress)
                .tint(.accentColor)
            Text("Page \(comic.currentPage + 1) of \(comic.pageCount)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 96)
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
