import SwiftUI

extension CollectionColor {
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color.opacity(0.95), color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// What a comic's context menu can do; views pass only the actions that make sense where they are.
struct ComicActionHandlers {
    var open: (ComicBook) -> Void
    var info: ((ComicBook) -> Void)? = nil
    var addToCollection: ((ComicBook) -> Void)? = nil
    /// Set inside a collection, enabling "Remove from Collection" and "Use as Cover".
    var collectionID: UUID? = nil
}

struct ComicActions: View {
    let comic: ComicBook
    let handlers: ComicActionHandlers
    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        Button { handlers.open(comic) } label: {
            switch comic.status {
            case .unread: Label("Read", systemImage: "book")
            case .inProgress: Label("Continue Reading", systemImage: "book")
            case .finished: Label("Read Again", systemImage: "arrow.counterclockwise")
            }
        }
        if let info = handlers.info {
            Button { info(comic) } label: { Label("Details", systemImage: "info.circle") }
        }
        if let add = handlers.addToCollection {
            Button { add(comic) } label: { Label("Add to Collection…", systemImage: "folder.badge.plus") }
        }
        if let collectionID = handlers.collectionID {
            Button {
                library.updateCollection(collectionID) { $0.coverComicID = comic.id }
            } label: { Label("Use as Collection Cover", systemImage: "photo") }
            Button {
                library.updateCollection(collectionID) { $0.remove([comic.id]) }
            } label: { Label("Remove from Collection", systemImage: "folder.badge.minus") }
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

// MARK: - Collection cards

struct CollectionsShelf: View {
    let collections: [ComicCollection]
    let open: (ComicCollection) -> Void
    let create: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collections")
                .font(.title3.bold())
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(collections) { collection in
                        Button { open(collection) } label: { CollectionCard(collection: collection) }
                            .buttonStyle(CoverButtonStyle())
                    }
                    Button(action: create) {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                .foregroundStyle(.tertiary)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 156, height: 108)
                            Text("New Collection")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(CoverButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }
}

struct CollectionCard: View {
    let collection: ComicCollection
    @EnvironmentObject private var library: LibraryManager

    private var previewComics: [ComicBook] {
        let comics = library.comics(in: collection)
        guard let coverID = collection.coverID, let cover = comics.first(where: { $0.id == coverID }) else {
            return Array(comics.prefix(3))
        }
        return [cover] + comics.filter { $0.id != coverID }.prefix(2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(collection.color.gradient)
                if previewComics.isEmpty {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    // Up to three covers fanned out, the chosen cover on top.
                    ForEach(Array(previewComics.enumerated().reversed()), id: \.element.id) { index, comic in
                        ComicCoverView(comic: comic, cornerRadius: 4)
                            .frame(width: 52)
                            .rotationEffect(.degrees(Double(index) * 8 - 8), anchor: .bottom)
                            .offset(x: CGFloat(index) * 22 - 22, y: 6)
                    }
                }
            }
            .frame(width: 156, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: collection.color.color.opacity(0.35), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(collection.comicIDs.count) \(collection.comicIDs.count == 1 ? "comic" : "comics")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 156, alignment: .leading)
        .foregroundStyle(.primary)
    }
}

// MARK: - Collection screen

struct CollectionView: View {
    let collectionID: UUID
    let actions: ComicActionHandlers

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("library.layout") private var layout: LibraryLayout = .grid
    @AppStorage("library.coverSize") private var coverSize: CoverSize = .medium
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var isEditing = false
    @State private var confirmDelete = false

    var body: some View {
        if let collection = library.collection(withID: collectionID) {
            content(collection)
        } else {
            Text("This collection was deleted.").foregroundStyle(.secondary)
        }
    }

    private func content(_ collection: ComicCollection) -> some View {
        let comics = library.comics(in: collection)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(collection, count: comics.count)
                if comics.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(collection.color.color)
                        Text("No Comics Yet").font(.headline)
                        Text("Long-press a comic in your library, or select several, and choose Add to Collection.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    ComicItemsView(entries: comics.map(LibraryEntry.comic), layout: layout, coverSize: coverSize,
                                   isSelecting: isSelecting, selection: $selection,
                                   actions: ComicActionHandlers(open: actions.open, info: actions.info,
                                                                addToCollection: actions.addToCollection,
                                                                collectionID: collection.id))
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(isSelecting ? "\(selection.count) Selected" : collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button("Done") { setSelecting(false) }.bold()
                } else {
                    Menu {
                        Button { isEditing = true } label: { Label("Edit Collection", systemImage: "pencil") }
                        if !comics.isEmpty {
                            Button { setSelecting(true) } label: { Label("Select Comics", systemImage: "checkmark.circle") }
                        }
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete Collection", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        library.markFinished(selection)
                        setSelecting(false)
                    } label: { Label("Mark as Read", systemImage: "checkmark.circle") }
                    .disabled(selection.isEmpty)
                    Spacer()
                    Button {
                        library.updateCollection(collection.id) { $0.remove(selection) }
                        setSelecting(false)
                    } label: {
                        Label("Remove", systemImage: "folder.badge.minus")
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            CollectionEditor(title: "Edit Collection", name: collection.name, color: collection.color) { name, color in
                library.updateCollection(collection.id) {
                    $0.name = name
                    $0.color = color
                }
            }
        }
        .confirmationDialog("Delete \u{201C}\(collection.name)\u{201D}?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) {
                library.deleteCollection(collection.id)
                dismiss()
            }
        } message: {
            Text("The comics stay in your library.")
        }
        #if DEBUG
        .onAppear {
            if !DemoLaunch.selectedTitles.isEmpty { setSelecting(true) }
        }
        #endif
    }

    private func header(_ collection: ComicCollection, count: Int) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(collection.color.gradient)
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name).font(.title2.bold())
                Text("\(count) \(count == 1 ? "comic" : "comics")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func setSelecting(_ selecting: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting = selecting
            selection = []
        }
    }
}

// MARK: - Editor

struct CollectionEditor: View {
    let title: String
    @State var name: String
    @State var color: CollectionColor
    let save: (String, CollectionColor) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    init(title: String, name: String = "", color: CollectionColor = .blue,
         save: @escaping (String, CollectionColor) -> Void) {
        self.title = title
        _name = State(initialValue: name)
        _color = State(initialValue: color)
        self.save = save
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(color.gradient)
                            .frame(width: 44, height: 44)
                            .overlay { Image(systemName: "folder.fill").foregroundStyle(.white) }
                        TextField("Collection Name", text: $name)
                            .font(.title3.weight(.semibold))
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(commit)
                    }
                    .padding(.vertical, 4)
                }
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 14) {
                        ForEach(CollectionColor.allCases) { option in
                            Button { color = option } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2.5)
                                            .padding(-5)
                                            .opacity(option == color ? 1 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.rawValue.capitalized)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit).disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { nameFocused = name.isEmpty }
        }
        .presentationDetents([.medium])
    }

    private func commit() {
        guard !trimmedName.isEmpty else { return }
        save(trimmedName, color)
        dismiss()
    }
}

// MARK: - Add to collection

/// Comic IDs waiting to be added to a collection (sheet item).
struct PendingCollectionAdd: Identifiable {
    let id = UUID()
    let comicIDs: [UUID]
}

struct AddToCollectionSheet: View {
    let comicIDs: [UUID]
    var onDone: () -> Void = {}

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { creating = true } label: {
                        Label("New Collection…", systemImage: "folder.badge.plus")
                    }
                }
                if !library.collections.isEmpty {
                    Section("Collections") {
                        ForEach(library.collections) { collection in
                            let alreadyIn = comicIDs.allSatisfy(collection.comicIDs.contains)
                            Button {
                                library.updateCollection(collection.id) { $0.add(comicIDs) }
                                finish()
                            } label: {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(collection.color.gradient)
                                        .frame(width: 32, height: 32)
                                        .overlay { Image(systemName: "folder.fill").font(.footnote).foregroundStyle(.white) }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(collection.name).foregroundStyle(.primary)
                                        Text("\(collection.comicIDs.count) comics")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if alreadyIn {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .disabled(alreadyIn)
                        }
                    }
                }
            }
            .navigationTitle(comicIDs.count == 1 ? "Add to Collection" : "Add \(comicIDs.count) Comics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $creating) {
                CollectionEditor(title: "New Collection") { name, color in
                    library.createCollection(named: name, color: color, comicIDs: comicIDs)
                    finish()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func finish() {
        onDone()
        dismiss()
    }
}

// MARK: - Series screen

struct SeriesView: View {
    let name: String
    let actions: ComicActionHandlers

    @EnvironmentObject private var library: LibraryManager
    @AppStorage("library.layout") private var layout: LibraryLayout = .grid
    @AppStorage("library.coverSize") private var coverSize: CoverSize = .medium
    @State private var selection: Set<UUID> = []

    private var issues: [ComicBook] {
        SeriesGrouping.ordered(library.comics.filter {
            SeriesGrouping.seriesName(for: $0).caseInsensitiveCompare(name) == .orderedSame
        })
    }

    /// The issue to pick up next: the one in progress, else the first unread.
    private var upNext: ComicBook? {
        issues.first { $0.status == .inProgress } ?? issues.first { $0.status == .unread }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    if let first = issues.first {
                        ComicCoverView(comic: first, cornerRadius: 8)
                            .frame(width: 96)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name).font(.title2.bold())
                        Text("\(issues.count) issues · \(issues.filter { $0.status == .finished }.count) read")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let writer = issues.compactMap({ $0.metadata?.writer }).first {
                            Text(writer).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let next = upNext {
                            Button { actions.open(next) } label: {
                                Label(next.status == .inProgress ? "Continue \(next.displayTitle)" : "Read \(next.displayTitle)",
                                      systemImage: "book.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ComicItemsView(entries: issues.map(LibraryEntry.comic), layout: layout, coverSize: coverSize,
                               isSelecting: false, selection: $selection, actions: actions)
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
