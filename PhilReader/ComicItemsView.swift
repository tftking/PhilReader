import SwiftUI

/// Library entries (comics and series stacks) shown as a grid or a list,
/// with optional multi-selection.
struct ComicItemsView: View {
    let entries: [LibraryEntry]
    let layout: LibraryLayout
    let coverSize: CoverSize
    let isSelecting: Bool
    @Binding var selection: Set<UUID>
    let actions: ComicActionHandlers
    var openSeries: (String) -> Void = { _ in }

    var body: some View {
        switch layout {
        case .grid:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: coverSize.minimumWidth,
                                                   maximum: coverSize.minimumWidth * 1.6),
                                         spacing: 18, alignment: .top)],
                      spacing: 26) {
                ForEach(entries) { entry in
                    item(entry) { selected in
                        switch entry {
                        case .comic(let comic): ComicGridItem(comic: comic, selected: selected)
                        case .series(let name, let comics): SeriesStackItem(name: name, comics: comics, selected: selected)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        case .list:
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    item(entry) { selected in
                        switch entry {
                        case .comic(let comic): ComicListRow(comic: comic, selected: selected)
                        case .series(let name, let comics): SeriesListRow(name: name, comics: comics, selected: selected)
                        }
                    }
                    Divider().padding(.leading, 92)
                }
            }
        }
    }

    /// Wraps an entry's cell in the right tap behaviour and context menu.
    @ViewBuilder
    private func item<Content: View>(_ entry: LibraryEntry,
                                     @ViewBuilder content: @escaping (Bool?) -> Content) -> some View {
        let ids = entry.comicIDs
        let selected: Bool? = isSelecting ? ids.allSatisfy(selection.contains) : nil
        Button {
            if isSelecting {
                if selected == true { selection.subtract(ids) } else { selection.formUnion(ids) }
            } else {
                switch entry {
                case .comic(let comic): actions.open(comic)
                case .series(let name, _): openSeries(name)
                }
            }
        } label: {
            content(selected)
        }
        .buttonStyle(CoverButtonStyle())
        .contextMenu {
            if !isSelecting, case .comic(let comic) = entry {
                ComicActions(comic: comic, handlers: actions)
            }
        }
    }
}

extension LibraryEntry {
    var comicIDs: [UUID] {
        switch self {
        case .comic(let comic): return [comic.id]
        case .series(_, let comics): return comics.map(\.id)
        }
    }
}

// MARK: - Grid cells

struct ComicGridItem: View {
    let comic: ComicBook
    /// `nil` when not selecting.
    var selected: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ComicCoverView(comic: comic)
                .overlay(alignment: .bottom) {
                    if comic.status == .inProgress {
                        ProgressBar(value: comic.progress).padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if comic.status == .finished && selected == nil {
                        FinishedBadge().padding(6)
                    }
                }
                .selectionOverlay(selected)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if comic.status == .unread {
                    UnreadDot()
                }
                Text(comic.displayTitle)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Text(comic.statusDetail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
    }
}

struct SeriesStackItem: View {
    let name: String
    let comics: [ComicBook]
    var selected: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                // Two offset "pages" behind the top cover suggest a stack.
                if comics.count > 2, let third = comics.dropFirst(2).first {
                    ComicCoverView(comic: third).padding(.horizontal, 10).offset(y: -10).opacity(0.55)
                }
                if let second = comics.dropFirst().first {
                    ComicCoverView(comic: second).padding(.horizontal, 5).offset(y: -5).opacity(0.8)
                }
                if let first = comics.first {
                    ComicCoverView(comic: first)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .bottomTrailing) {
                Text("\(comics.count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .foregroundStyle(.white)
                    .padding(6)
            }
            .selectionOverlay(selected)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if comics.contains(where: { $0.status == .unread }) { UnreadDot() }
                Text(name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Text(seriesDetail(comics))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - List rows

struct ComicListRow: View {
    let comic: ComicBook
    var selected: Bool? = nil

    var body: some View {
        HStack(spacing: 14) {
            SelectionMark(selected: selected)
            ComicCoverView(comic: comic, cornerRadius: 5)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(comic.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = comic.subtitle ?? comic.metadata?.writer {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if comic.status == .inProgress {
                        ProgressView(value: comic.progress)
                            .frame(maxWidth: 90)
                    }
                    Text(comic.statusDetail)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if comic.status == .unread {
                UnreadDot()
            } else if comic.status == .finished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
    }
}

struct SeriesListRow: View {
    let name: String
    let comics: [ComicBook]
    var selected: Bool? = nil

    var body: some View {
        HStack(spacing: 14) {
            SelectionMark(selected: selected)
            ZStack {
                if let second = comics.dropFirst().first {
                    ComicCoverView(comic: second, cornerRadius: 5).offset(x: 6, y: -4).opacity(0.7)
                }
                if let first = comics.first {
                    ComicCoverView(comic: first, cornerRadius: 5)
                }
            }
            .frame(width: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(seriesDetail(comics))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
    }
}

// MARK: - Small pieces

private func seriesDetail(_ comics: [ComicBook]) -> String {
    let unread = comics.filter { $0.status != .finished }.count
    let issues = "\(comics.count) issues"
    return unread == 0 ? "\(issues) · All read" : "\(issues) · \(unread) to read"
}

extension ComicBook {
    /// Linked comics that haven't been downloaded yet don't know their page count.
    var isCloudOnly: Bool { isLinked && pageCount == 0 }

    var statusDetail: String {
        if isCloudOnly { return "In iCloud" }
        switch status {
        case .unread: return "\(pageCount) pages"
        case .inProgress: return "\(Int((progress * 100).rounded()))% read"
        case .finished: return "Finished"
        }
    }
}

struct UnreadDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .accessibilityLabel("Unread")
    }
}

private struct FinishedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .shadow(radius: 2)
    }
}

struct ProgressBar: View {
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

/// Leading checkmark shown on list rows while selecting.
private struct SelectionMark: View {
    let selected: Bool?

    var body: some View {
        if let selected {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }
}

private extension View {
    /// Dims unselected covers and adds a checkmark while selecting.
    @ViewBuilder
    func selectionOverlay(_ selected: Bool?) -> some View {
        if let selected {
            self
                .opacity(selected ? 1 : 0.75)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, selected ? Color.accentColor : Color.black.opacity(0.35))
                        .shadow(radius: 2)
                        .padding(6)
                }
        } else {
            self
        }
    }
}
