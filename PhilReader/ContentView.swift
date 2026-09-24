import SwiftUI

enum AppTab: String {
    case library, collections, settings
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
    @AppStorage("app.tab") private var tab: AppTab = .library

    var body: some View {
        TabView(selection: $tab) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(AppTab.library)
            CollectionsTab()
                .tabItem { Label("Collections", systemImage: "square.stack.fill") }
                .tag(AppTab.collections)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .environmentObject(coordinator)
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
                tab = DemoLaunch.tab ?? (DemoLaunch.collectionName != nil ? .collections : .library)
            }
        }
        #endif
    }
}

// MARK: - Collections tab

struct CollectionsTab: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var coordinator: ReadingCoordinator
    @State private var path = NavigationPath()
    @State private var creating = false

    private let columns = [GridItem(.adaptive(minimum: 158, maximum: 220), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.collections.isEmpty {
                    empty
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(library.collections) { collection in
                                NavigationLink(value: collection.id) {
                                    CollectionCard(collection: collection, width: nil)
                                }
                                .buttonStyle(CoverButtonStyle())
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Collection")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                CollectionView(collectionID: id, actions: coordinator.actions)
            }
            .sheet(isPresented: $creating) {
                CollectionEditor(title: "New Collection") { name, color in
                    let collection = library.createCollection(named: name, color: color)
                    path.append(collection.id)
                }
            }
            #if DEBUG
            .task {
                await library.prepareDemoLibrary()
                if let name = DemoLaunch.collectionName, path.isEmpty,
                   let collection = library.collections.first(where: { $0.name == name }) {
                    path.append(collection.id)
                }
            }
            #endif
        }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("No Collections Yet")
                .font(.system(.title2, design: .rounded).bold())
            Text("Group comics however you like: favourites,\na reading list, a publisher, a story arc.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { creating = true } label: {
                Label("New Collection", systemImage: "plus").font(.headline).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
