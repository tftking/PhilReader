import SwiftUI
import UniformTypeIdentifiers

/// Which comics a grid shows.
enum LibraryScope: Hashable {
    /// Everything in the library.
    case all
    /// Comics imported into the app (not in a linked folder).
    case device
    /// Comics in one linked library folder.
    case folder(UUID)
}

/// Screens pushed inside the Library and Search tabs.
enum LibraryRoute: Hashable {
    case comics(LibraryScope)
    case collection(UUID)
    case series(String)
    case allSeries
    case finished
    case webServer
}

/// Comics in a scope as a grid or list, with search, filters, sorting and selection.
struct ComicsGridScreen: View {
    let scope: LibraryScope
    let openSeries: (String) -> Void

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var coordinator: ReadingCoordinator
    @AppStorage("library.sort") private var sort: LibrarySort = .recentlyRead
    @AppStorage("library.filter") private var filter: LibraryFilter = .all
    @AppStorage("library.layout") private var layout: LibraryLayout = .grid
    @AppStorage("library.coverSize") private var coverSize: CoverSize = .medium
    @AppStorage("library.groupSeries") private var groupsSeries = true

    @State private var search = ""
    @State private var showingFilePicker = false
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var isDropTargeted = false

    static let importableTypes: [UTType] =
        ["cbz", "cbr", "cb7", "rar", "7z"].compactMap { UTType(filenameExtension: $0) } + [.zip, .pdf, .epub, .folder]

    private var scopedComics: [ComicBook] {
        switch scope {
        case .all: return library.comics
        case .device: return library.comics.filter { !$0.isLinked }
        case .folder(let id): return library.comics.filter { $0.linkedFolderID == id }
        }
    }
    private var title: String {
        switch scope {
        case .all: return "All Comics"
        case .device: return "On My iPhone"
        case .folder(let id): return library.linkedFolders.first { $0.id == id }?.name ?? "Folder"
        }
    }
    private var query: LibraryQuery { LibraryQuery(search: search, sort: sort, filter: filter) }
    private var visibleComics: [ComicBook] { query.apply(to: scopedComics) }
    private var entries: [LibraryEntry] {
        groupsSeries && search.isEmpty ? LibraryEntry.grouped(visibleComics) : visibleComics.map(LibraryEntry.comic)
    }
    private var actions: ComicActionHandlers { coordinator.actions }

    var body: some View {
        Group {
            if scopedComics.isEmpty {
                emptyLibrary
            } else {
                content
            }
        }
        .navigationTitle(isSelecting ? "\(selection.count) Selected" : title)
        .toolbar { toolbar }
        .overlay { if isDropTargeted { DropTargetOverlay() } }
        .dropDestination(for: URL.self) { urls, _ in
            Task { for url in urls { await library.importComic(from: url) } }
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: Self.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { for url in urls { await library.importComic(from: url) } }
            }
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
        .task {
            await library.prepareDemoLibrary()
            if !DemoLaunch.selectedTitles.isEmpty && !isSelecting {
                isSelecting = true
                selection = Set(library.comics.filter { DemoLaunch.selectedTitles.contains($0.title) }.map(\.id))
            }
        }
        #endif
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FilterBar(selection: $filter, comics: scopedComics)

                if entries.isEmpty {
                    noMatches
                } else {
                    ComicItemsView(entries: entries, layout: layout, coverSize: coverSize,
                                   isSelecting: isSelecting, selection: $selection, actions: actions,
                                   openSeries: openSeries)
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
                if !scopedComics.isEmpty {
                    Menu {
                        viewOptions
                    } label: {
                        Image(systemName: "ellipsis")
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
            Text(scope == .all ? "Your Library Is Empty" : "No Comics Here Yet")
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
