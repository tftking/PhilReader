import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryManager
    @State private var showingFilePicker = false
    @State private var selectedComic: ComicBook?
    @State private var showingReader = false

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if library.comics.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(library.comics) { comic in
                                ComicCell(comic: comic)
                                    .onTapGesture {
                                        selectedComic = comic
                                        showingReader = true
                                    }
                            }
                        }
                        .padding(16)
                    }
                }

                if library.isImporting {
                    importingOverlay
                }
            }
            .navigationTitle("PhilReader")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingFilePicker = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                }
                if !library.comics.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "cbz") ?? .zip, .zip],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls { Task { await library.importComic(from: url) } }
                }
            }
            .alert("Import Error", isPresented: .constant(library.importError != nil)) {
                Button("OK") { library.importError = nil }
            } message: {
                Text(library.importError ?? "")
            }
            .fullScreenCover(isPresented: $showingReader) {
                if let comic = selectedComic { ReaderView(comic: comic) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical").font(.system(size: 64)).foregroundStyle(.secondary)
            Text("No Comics Yet").font(.title2.bold())
            Text("Tap + to import a .cbz file\nor open one from the Files app.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showingFilePicker = true } label: {
                Label("Import Comic", systemImage: "plus.circle.fill")
                    .font(.headline).padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.accentColor).foregroundStyle(.white).clipShape(Capsule())
            }
        }
        .padding()
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().progressViewStyle(.circular).scaleEffect(1.4).tint(.white)
                Text("Importing…").font(.headline).foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Comic Cell

struct ComicCell: View {
    let comic: ComicBook
    @EnvironmentObject private var library: LibraryManager
    @State private var cover: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                coverImage.frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 4, y: 2)
                if comic.progress > 0 {
                    Text("\(Int(comic.progress * 100))%")
                        .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.65)).foregroundStyle(.white)
                        .clipShape(Capsule()).padding(6)
                }
            }
            Text(comic.title).font(.caption.weight(.semibold)).lineLimit(2)
            if comic.pageCount > 0 {
                ProgressView(value: comic.progress).tint(.accentColor).scaleEffect(x: 1, y: 0.6)
            }
        }
        .task { cover = await library.coverImage(for: comic) }
        .contextMenu {
            Button(role: .destructive) {
                if let idx = library.comics.firstIndex(where: { $0.id == comic.id }) {
                    library.delete(at: IndexSet([idx]))
                }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let cover {
            Image(uiImage: cover).resizable().scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill))
                .overlay(Image(systemName: "book.closed.fill").font(.system(size: 36)).foregroundStyle(.tertiary))
        }
    }
}
