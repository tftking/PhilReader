import SwiftUI

enum AppTab: String {
    case readingNow, library, search, settings
}

/// Presents the reader, comic details and "Add to Collection" for every tab,
/// so any screen can open a comic.
@MainActor
final class ReadingCoordinator: ObservableObject {
    @Published var readingComic: ComicBook?
    @Published var infoComic: ComicBook?
    @Published var pendingAdd: PendingCollectionAdd?
    /// A comic to open once the current sheet or reader has been dismissed.
    var pendingRead: ComicBook?

    private let library: LibraryManager

    init(library: LibraryManager = .shared) {
        self.library = library
    }

    var actions: ComicActionHandlers {
        ComicActionHandlers(open: { [weak self] in self?.open($0) },
                            info: { [weak self] in self?.infoComic = $0 },
                            addToCollection: { [weak self] in self?.addToCollection([$0.id]) })
    }

    func open(_ comic: ComicBook) {
        if comic.isFinished { library.restart(comic.id) }
        readingComic = library.comic(withID: comic.id) ?? comic
    }

    func addToCollection(_ ids: [UUID], onDone: @escaping () -> Void = {}) {
        pendingAdd = PendingCollectionAdd(comicIDs: ids, onDone: onDone)
    }

    func openPending() {
        guard let comic = pendingRead else { return }
        pendingRead = nil
        open(comic)
    }
}

struct ContentView: View {
    @EnvironmentObject private var library: LibraryManager
    @StateObject private var coordinator = ReadingCoordinator()
    @AppStorage("app.tab") private var tab: AppTab = .readingNow

    var body: some View {
        TabView(selection: $tab) {
            ReadingNowView(showLibrary: { tab = .library })
                .tabItem { Label("Reading Now", systemImage: "book") }
                .tag(AppTab.readingNow)
            LibraryHomeView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppTab.library)
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environmentObject(coordinator)
        .overlay { if library.isImporting { ImportingOverlay() } }
        .alert("Couldn't Import", isPresented: Binding(
            get: { library.importError != nil },
            set: { if !$0 { library.importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.importError ?? "")
        }
        .sheet(item: $coordinator.pendingAdd) { pending in
            AddToCollectionSheet(comicIDs: pending.comicIDs, onDone: pending.onDone)
        }
        .sheet(item: $coordinator.infoComic, onDismiss: coordinator.openPending) { comic in
            ComicDetailView(comicID: comic.id) { selected in
                coordinator.pendingRead = selected
                coordinator.infoComic = nil
            }
        }
        .fullScreenCover(item: $coordinator.readingComic, onDismiss: coordinator.openPending) { comic in
            ReaderView(comic: comic, fileURL: library.fileURL(for: comic)) { next in
                coordinator.pendingRead = next
            }
        }
        #if DEBUG
        .onAppear {
            // Each demo launch picks its tab; the saved tab would otherwise carry over between shots.
            if DemoLaunch.importsLibrary {
                tab = DemoLaunch.tab ?? (DemoLaunch.browsesLibrary ? .library : .readingNow)
            }
        }
        .task { await prepareDemo() }
        #endif
    }

    #if DEBUG
    private func prepareDemo() async {
        await library.prepareDemoLibrary()
        if let title = DemoLaunch.openTitle, let comic = library.comics.first(where: { $0.title == title }) {
            if let mode = DemoLaunch.mode { library.setReadingMode(comic.id, mode) }
            if let page = DemoLaunch.page { library.updateProgress(for: comic.id, page: max(page - 1, 0)) }
            coordinator.readingComic = library.comic(withID: comic.id)
        } else if let title = DemoLaunch.infoTitle, let comic = library.comics.first(where: { $0.title == title }) {
            coordinator.infoComic = comic
        }
    }
    #endif
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
