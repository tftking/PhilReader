import SwiftUI

/// The first tab: what you're reading, what's next and what you've finished.
struct ReadingNowView: View {
    let showLibrary: () -> Void

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var coordinator: ReadingCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var path = NavigationPath()

    private var actions: ComicActionHandlers { coordinator.actions }
    private var inProgress: [ComicBook] { LibraryQuery.continueReading(library.comics, limit: 20) }

    /// The next unread issue of each series you've finished an issue of, newest first.
    private var nextUp: [ComicBook] {
        let finished = library.comics
            .filter { $0.status == .finished }
            .sorted { ($0.lastOpened ?? $0.dateAdded) > ($1.lastOpened ?? $1.dateAdded) }
        var seen: Set<String> = []
        var result: [ComicBook] = []
        for comic in finished {
            let series = SeriesGrouping.seriesName(for: comic).lowercased()
            guard !seen.contains(series) else { continue }
            let issues = SeriesGrouping.ordered(library.comics.filter {
                SeriesGrouping.seriesName(for: $0).lowercased() == series
            })
            // Series you're partway through already show up under Pick Up Where You Left Off.
            guard !issues.contains(where: { $0.status == .inProgress }),
                  let index = issues.firstIndex(where: { $0.id == comic.id }),
                  let next = issues[(index + 1)...].first(where: { $0.status == .unread }) else { continue }
            seen.insert(series)
            result.append(next)
        }
        return result
    }

    private var finished: [ComicBook] {
        library.comics
            .filter { $0.status == .finished }
            .sorted { ($0.lastOpened ?? $0.dateAdded) > ($1.lastOpened ?? $1.dateAdded) }
    }

    private var hero: ComicBook? { inProgress.first ?? nextUp.first }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let hero {
                    content(hero: hero)
                } else {
                    empty
                }
            }
            .navigationTitle("Reading Now")
            .libraryDestinations(path: $path, actions: actions)
        }
    }

    private func content(hero: ComicBook) -> some View {
        ScrollView {
            if horizontalSizeClass == .regular {
                // iPad: the cover beside the lists, rather than a card as wide as the screen.
                HStack(alignment: .top, spacing: 12) {
                    heroCard(hero)
                        .frame(width: 380)
                    shelves(excluding: hero)
                }
                .padding(.top, 6)
                .padding(.bottom, 32)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 30) {
                    heroCard(hero)
                    shelves(excluding: hero)
                }
                .padding(.top, 6)
                .padding(.bottom, 32)
            }
        }
    }

    private func heroCard(_ hero: ComicBook) -> some View {
        HeroCard(comic: hero) { actions.open(hero) }
            .contextMenu { ComicActions(comic: hero, handlers: actions) }
            .padding(.horizontal, 20)
    }

    private func shelves(excluding hero: ComicBook) -> some View {
        let upNext = nextUp.filter { $0.id != hero.id }
        let pickUp = inProgress.filter { $0.id != hero.id }
        return VStack(alignment: .leading, spacing: 30) {
            if !upNext.isEmpty {
                shelf("Next Up") {
                    ForEach(upNext) { comic in
                        row(comic, detail: "Next in \(SeriesGrouping.seriesName(for: comic))", trailing: nil)
                    }
                }
            }
            if !pickUp.isEmpty {
                shelf("Pick Up Where You Left Off") {
                    ForEach(pickUp) { comic in
                        row(comic, detail: comic.lastOpened.map(ComicRow.relative) ?? "Not started",
                            trailing: "\(Int((comic.progress * 100).rounded()))%")
                    }
                }
            }
            if !finished.isEmpty {
                shelf("Finished", seeAll: finished.count > 3 ? LibraryRoute.finished : nil) {
                    ForEach(finished.prefix(3)) { comic in
                        row(comic, detail: comic.lastOpened.map(ComicRow.relative) ?? "Finished", trailing: nil)
                    }
                }
            }
        }
    }

    private func shelf<Content: View>(_ title: String, seeAll: LibraryRoute? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title2.bold())
                Spacer()
                if let seeAll {
                    NavigationLink("See All", value: seeAll).font(.body)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
            VStack(spacing: 0) { content() }
        }
    }

    private func row(_ comic: ComicBook, detail: String, trailing: String?) -> some View {
        Button { actions.open(comic) } label: {
            VStack(spacing: 0) {
                ComicRow(comic: comic, detail: detail, trailing: trailing)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                Divider().padding(.leading, 20 + 56 + 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { ComicActions(comic: comic, handlers: actions) }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "book")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
            Text(library.comics.isEmpty ? "Nothing to Read Yet" : "Start Something New")
                .font(.title2.bold())
            Text(library.comics.isEmpty
                 ? "Import comics or add a library folder,\nthen pick up here where you left off."
                 : "Comics you're reading show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: showLibrary) {
                Text("Go to Library").font(.headline).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The comic you're reading: a large cover with its title over a fade, and progress underneath.
private struct HeroCard: View {
    let comic: ComicBook
    let open: () -> Void

    @EnvironmentObject private var library: LibraryManager
    @State private var cover: UIImage?

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                Color(white: 0.16)
                    .aspectRatio(0.82, contentMode: .fit)
                    .overlay {
                        if let cover {
                            // Pinned to the top so the cover's title stays in view.
                            GeometryReader { proxy in
                                Image(uiImage: cover)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                            }
                            .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let series = comic.metadata?.series, comic.displayTitle != series {
                                Text(series.uppercased())
                                    .font(.caption.weight(.bold))
                                    .tracking(1)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            Text(comic.subtitle.map { "\(comic.displayTitle): \($0)" } ?? comic.displayTitle)
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                                .padding(.top, -60)
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.3), radius: 18, y: 10)

                HStack(spacing: 12) {
                    ProgressView(value: comic.progress)
                        .tint(.accentColor)
                    Text(comic.status == .inProgress
                         ? "Page \(comic.currentPage + 1) of \(comic.pageCount)"
                         : "Up Next")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(CoverButtonStyle())
        .task(id: comic.id) {
            let image = await library.coverImage(for: comic)
            withAnimation(.easeOut(duration: 0.25)) { cover = image }
        }
    }
}

/// A comic as a list row: small cover, title, detail and an optional trailing value.
struct ComicRow: View {
    let comic: ComicBook
    let detail: String
    let trailing: String?

    var body: some View {
        HStack(spacing: 14) {
            ComicCoverView(comic: comic, cornerRadius: 4)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(comic.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = comic.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Today", "Yesterday" or "12 Days Ago", as Panels shows it.
    static func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) Days Ago"
        }
    }
}
