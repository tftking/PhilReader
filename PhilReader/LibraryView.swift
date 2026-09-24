import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryManager
    @AppStorage("library.sort") private var sort: LibrarySort = .recentlyRead
    @AppStorage("library.filter") private var filter: LibraryFilter = .all
    @State private var search = ""
    @State private var showingFilePicker = false
    @State private var readingComic: ComicBook?
    @State private var infoComic: ComicBook?
    @State private var pendingRead: ComicBook?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 18, alignment: .top)]

    private var query: LibraryQuery { LibraryQuery(search: search, sort: sort, filter: filter) }
    private var visibleComics: [ComicBook] { query.apply(to: library.comics) }
    private var continueReading: [ComicBook] { LibraryQuery.continueReading(library.comics) }
    private var showsShelf: Bool { search.isEmpty && filter == .all && !continueReading.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if library.comics.isEmpty {
                    emptyLibrary
                } else {
                    content
                }
            }
            .navigationTitle("Library")
            .toolbar { toolbar }
            .overlay { if library.isImporting { ImportingOverlay() } }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "cbz") ?? .zip, .zip],
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
                    ContinueReadingShelf(comics: continueReading, open: open, info: showInfo)
                }

                VStack(alignment: .leading, spacing: 16) {
                    FilterBar(selection: $filter, comics: library.comics)

                    if visibleComics.isEmpty {
                        noMatches
                    } else {
                        LazyVGrid(columns: columns, spacing: 26) {
                            ForEach(visibleComics) { comic in
                                Button { open(comic) } label: { ComicGridItem(comic: comic) }
                                    .buttonStyle(CoverButtonStyle())
                                    .contextMenu { ComicActions(comic: comic, open: open, info: showInfo) }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .searchable(text: $search, prompt: "Titles, series, creators")
        .animation(.default, value: filter)
        .animation(.default, value: sort)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if !library.comics.isEmpty {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
            }
            Button { showingFilePicker = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Import Comics")
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Your Library Is Empty")
                .font(.title2.bold())
            Text("Import .cbz files from the Files app, or open\none from another app with PhilReader.")
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

    #if DEBUG
    private func prepareDemo() async {
        await library.prepareDemoLibrary()
        if let title = DemoLaunch.openTitle, let comic = library.comics.first(where: { $0.title == title }) {
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
    let open: (ComicBook) -> Void
    let info: (ComicBook) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Reading")
                .font(.title3.bold())
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(comics) { comic in
                        Button { open(comic) } label: { card(comic) }
                            .buttonStyle(CoverButtonStyle())
                            .contextMenu { ComicActions(comic: comic, open: open, info: info) }
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

// MARK: - Grid

private struct ComicGridItem: View {
    let comic: ComicBook

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ComicCoverView(comic: comic)
                .overlay(alignment: .bottom) {
                    if comic.status == .inProgress {
                        ProgressBar(value: comic.progress)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if comic.status == .finished {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if comic.status == .unread {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("Unread")
                }
                Text(comic.displayTitle)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
    }

    private var detail: String {
        switch comic.status {
        case .unread: return "\(comic.pageCount) pages"
        case .inProgress: return "\(Int((comic.progress * 100).rounded()))% read"
        case .finished: return "Finished"
        }
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.45))
                Capsule().fill(.white)
                    .frame(width: max(proxy.size.width * value, 4))
            }
        }
        .frame(height: 4)
        .shadow(color: .black.opacity(0.3), radius: 2)
    }
}

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

// MARK: - Shared pieces

struct ComicActions: View {
    let comic: ComicBook
    let open: (ComicBook) -> Void
    var info: ((ComicBook) -> Void)? = nil
    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        Button { open(comic) } label: {
            switch comic.status {
            case .unread: Label("Read", systemImage: "book")
            case .inProgress: Label("Continue Reading", systemImage: "book")
            case .finished: Label("Read Again", systemImage: "arrow.counterclockwise")
            }
        }
        if let info {
            Button { info(comic) } label: { Label("Details", systemImage: "info.circle") }
        }
        Divider()
        if comic.status == .finished {
            Button { library.markUnread(comic.id) } label: { Label("Mark as Unread", systemImage: "circle") }
        } else {
            Button { library.markFinished(comic.id) } label: { Label("Mark as Read", systemImage: "checkmark.circle") }
        }
        Divider()
        Button(role: .destructive) { library.delete(comic) } label: { Label("Delete", systemImage: "trash") }
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
