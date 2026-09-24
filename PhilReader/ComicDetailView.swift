import SwiftUI

/// Details for one comic: cover, metadata, summary and a big read button.
struct ComicDetailView: View {
    let comicID: UUID
    let read: (ComicBook) -> Void

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss
    @State private var backdrop: UIImage?

    var body: some View {
        NavigationStack {
            if let comic = library.comic(withID: comicID) {
                content(comic)
            } else {
                Text("This comic is no longer in your library.")
                    .foregroundStyle(.secondary)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func content(_ comic: ComicBook) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                ComicCoverView(comic: comic, cornerRadius: 10)
                    .frame(width: 190)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Text(comic.displayTitle)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if let subtitle = comic.subtitle {
                        Text(subtitle)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    let creditLine = credits(comic)
                    if !creditLine.isEmpty {
                        Text(creditLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)

                readButton(comic)

                stats(comic)

                if let summary = comic.metadata?.summary {
                    section("Summary") {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if comic.metadata?.hasCreators == true {
                    section("Details") { creators(comic) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background { backdropView.ignoresSafeArea() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ComicActions(comic: comic, handlers: ComicActionHandlers(open: read))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: comic.id) { backdrop = await library.coverImage(for: comic) }
    }

    private func credits(_ comic: ComicBook) -> String {
        let parts: [String?] = [comic.metadata?.writer, comic.metadata?.publisher, comic.metadata?.year.map(String.init)]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func readButton(_ comic: ComicBook) -> some View {
        Button { read(comic) } label: {
            Label(readTitle(comic), systemImage: comic.status == .finished ? "arrow.counterclockwise" : "book.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    private func readTitle(_ comic: ComicBook) -> String {
        switch comic.status {
        case .unread: return "Read"
        case .inProgress: return "Continue · Page \(comic.currentPage + 1)"
        case .finished: return "Read Again"
        }
    }

    private func stats(_ comic: ComicBook) -> some View {
        HStack(spacing: 0) {
            stat(value: "\(comic.pageCount)", label: "Pages")
            Divider().frame(height: 32)
            stat(value: "\(Int((comic.progress * 100).rounded()))%", label: "Read")
            Divider().frame(height: 32)
            stat(value: comic.dateAdded.formatted(.dateTime.month(.abbreviated).day()), label: "Added")
        }
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func creators(_ comic: ComicBook) -> some View {
        VStack(spacing: 0) {
            ForEach(creatorRows(comic), id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
                .padding(.vertical, 10)
                if row.0 != creatorRows(comic).last?.0 { Divider() }
            }
        }
        .padding(.horizontal, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func creatorRows(_ comic: ComicBook) -> [(String, String)] {
        let m = comic.metadata
        let rows: [(String, String?)] = [
            ("Series", m?.series), ("Volume", m?.volume.map(String.init)), ("Number", m?.number),
            ("Writer", m?.writer), ("Artist", m?.artist), ("Publisher", m?.publisher),
            ("Year", m?.year.map(String.init)),
            ("Direction", m?.readsRightToLeft.map { $0 ? "Right to left" : "Left to right" }),
        ]
        return rows.compactMap { row in row.1.map { (row.0, $0) } }
    }

    /// The cover, blurred and darkened, behind the whole sheet.
    private var backdropView: some View {
        ZStack {
            Color(.systemBackground)
            if let backdrop {
                Image(uiImage: backdrop)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(0.55)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.clear, Color(.systemBackground)], startPoint: .top, endPoint: .center)
        }
    }
}
