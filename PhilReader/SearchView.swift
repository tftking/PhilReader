import SwiftUI

/// Searches comics, series and collections by title, series, creator and publisher.
struct SearchView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var coordinator: ReadingCoordinator
    @State private var path = NavigationPath()
    @State private var text = ""

    private var actions: ComicActionHandlers { coordinator.actions }
    private var term: String { text.trimmingCharacters(in: .whitespaces) }

    private var comics: [ComicBook] {
        LibraryQuery(search: term, sort: .title).apply(to: library.comics)
    }
    private var series: [(name: String, issues: [ComicBook])] {
        var buckets: [String: [ComicBook]] = [:]
        for comic in library.comics {
            let name = SeriesGrouping.seriesName(for: comic)
            if name.localizedStandardContains(term) { buckets[name, default: []].append(comic) }
        }
        return buckets
            .filter { $0.value.count > 1 }
            .map { (name: $0.key, issues: SeriesGrouping.ordered($0.value)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var collections: [ComicCollection] {
        library.collections.filter { $0.name.localizedStandardContains(term) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if term.isEmpty {
                    suggestions
                } else {
                    results
                }
            }
            .listStyle(.plain)
            .overlay {
                if !term.isEmpty && comics.isEmpty && series.isEmpty && collections.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No Results for \u{201C}\(term)\u{201D}")
                            .font(.headline)
                        Text("Check the spelling or try a series, writer or artist.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $text, prompt: "Comics, series, creators")
            .libraryDestinations(path: $path, actions: actions)
            #if DEBUG
            .onAppear {
                if text.isEmpty, let demo = DemoLaunch.searchText { text = demo }
            }
            #endif
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let recent = Array(library.comics
            .filter { $0.lastOpened != nil }
            .sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
            .prefix(6))
        if !recent.isEmpty {
            Section {
                ForEach(recent) { comic in comicRow(comic) }
            } header: {
                header("Recently Read")
            }
        }
        let creators = Array(Set(library.comics.flatMap { [$0.metadata?.writer, $0.metadata?.artist].compactMap { $0 } })
            .sorted().prefix(8))
        if !creators.isEmpty {
            Section {
                ForEach(creators, id: \.self) { creator in
                    Button { text = creator } label: {
                        Label(creator, systemImage: "person")
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                header("Creators")
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if !collections.isEmpty {
            Section {
                ForEach(collections) { collection in
                    NavigationLink(value: LibraryRoute.collection(collection.id)) {
                        LibraryRow(collection.name, systemImage: "square.stack.3d.up", tint: collection.color.color,
                                   count: collection.comicIDs.count)
                    }
                }
            } header: {
                header("Collections")
            }
        }
        if !series.isEmpty {
            Section {
                ForEach(series, id: \.name) { entry in
                    NavigationLink(value: LibraryRoute.series(entry.name)) {
                        HStack(spacing: 14) {
                            if let first = entry.issues.first {
                                ComicCoverView(comic: first, cornerRadius: 4).frame(width: 44)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).font(.headline)
                                Text("\(entry.issues.count) issues").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                header("Series")
            }
        }
        if !comics.isEmpty {
            Section {
                ForEach(comics) { comic in comicRow(comic) }
            } header: {
                header("Comics")
            }
        }
    }

    private func comicRow(_ comic: ComicBook) -> some View {
        Button { actions.open(comic) } label: {
            ComicRow(comic: comic, detail: detail(for: comic), trailing: nil)
        }
        .contextMenu { ComicActions(comic: comic, handlers: actions) }
    }

    private func detail(for comic: ComicBook) -> String {
        switch comic.status {
        case .unread: return comic.metadata?.writer ?? "Unread"
        case .inProgress: return "\(Int((comic.progress * 100).rounded()))% read"
        case .finished: return "Finished"
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}
