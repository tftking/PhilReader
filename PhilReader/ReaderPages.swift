import SwiftUI

// MARK: - Paged

/// One page at a time, swiped horizontally. The last "page" is the end card.
struct PagedReader: View {
    @ObservedObject var model: ReaderModel
    @Binding var currentIndex: Int
    let isRightToLeft: Bool
    let liveText: Bool
    let onTap: (CGFloat) -> Void
    let end: EndOfComicCard

    /// Pages in on-screen order. For right-to-left reading the order is
    /// reversed, so swiping right moves forward like a printed manga.
    private var displayOrder: [Int] {
        let indices = Array(0...model.pageCount)
        return isRightToLeft ? indices.reversed() : indices
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(displayOrder, id: \.self) { index in
                Group {
                    if index == model.pageCount {
                        end
                    } else {
                        PageView(index: index, model: model, liveText: liveText, onTap: onTap)
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .id(isRightToLeft)
    }
}

private struct PageView: View {
    let index: Int
    let model: ReaderModel
    let liveText: Bool
    let onTap: (CGFloat) -> Void

    @State private var image: UIImage?
    @State private var failed = false

    init(index: Int, model: ReaderModel, liveText: Bool, onTap: @escaping (CGFloat) -> Void) {
        self.index = index
        self.model = model
        self.liveText = liveText
        self.onTap = onTap
        _image = State(initialValue: model.cachedImage(at: index))
    }

    var body: some View {
        ZStack {
            if let image {
                ZoomablePage(image: image, liveText: liveText, onTap: onTap)
                    .transition(.opacity)
            } else {
                GeometryReader { proxy in
                    PagePlaceholder(number: index + 1, failed: failed)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in
                            onTap(tap.location.x / max(proxy.size.width, 1))
                        })
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .task(id: index) {
            guard image == nil else { return }
            let loaded = await model.image(at: index)
            withAnimation(.easeOut(duration: 0.25)) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}

// MARK: - Vertical

/// Continuous vertical scroll with no gaps, for webtoons and long strips.
struct VerticalReader: View {
    @ObservedObject var model: ReaderModel
    @Binding var currentIndex: Int
    /// Changes whenever the reader should scroll to `currentIndex` (slider, page browser).
    let jumpToken: Int
    let onTap: () -> Void
    let end: EndOfComicCard

    @State private var isJumping = false

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<model.pageCount, id: \.self) { index in
                            VerticalPage(index: index, model: model, width: outer.size.width)
                                .id(index)
                                .reportOffset(index)
                        }
                        end
                            .frame(width: outer.size.width, height: max(outer.size.height * 0.85, 420))
                            .id(model.pageCount)
                            .reportOffset(model.pageCount)
                    }
                }
                .coordinateSpace(name: VerticalReader.space)
                .onPreferenceChange(PageOffsetsKey.self) { offsets in
                    guard !isJumping else { return }
                    // The current page is the last one whose top edge has passed 40% of the screen.
                    let threshold = outer.size.height * 0.4
                    let visible = offsets.filter { $0.value <= threshold }.map(\.key).max() ?? 0
                    if visible != currentIndex { currentIndex = visible }
                }
                .onAppear {
                    DispatchQueue.main.async { proxy.scrollTo(currentIndex, anchor: .top) }
                }
                .onChange(of: jumpToken) { _ in
                    isJumping = true
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(currentIndex, anchor: .top) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isJumping = false }
                }
                .onTapGesture { onTap() }
            }
        }
    }

    static let space = "verticalReader"
}

private struct VerticalPage: View {
    let index: Int
    let model: ReaderModel
    let width: CGFloat

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        let ratio = image.map { $0.size.width / max($0.size.height, 1) } ?? model.aspectRatio(at: index) ?? 2 / 3
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else {
                PagePlaceholder(number: index + 1, failed: failed)
            }
        }
        .frame(width: width, height: width / max(ratio, 0.05))
        .task(id: index) {
            if image == nil { image = model.cachedImage(at: index) }
            guard image == nil else { return }
            let loaded = await model.image(at: index)
            withAnimation(.easeOut(duration: 0.2)) {
                image = loaded
                failed = loaded == nil
            }
        }
        // Off-screen pages drop their bitmap (the model's cache may keep it),
        // so memory stays flat through long webtoons.
        .onDisappear { image = nil }
    }
}

private struct PageOffsetsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func reportOffset(_ index: Int) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: PageOffsetsKey.self,
                                   value: [index: proxy.frame(in: .named(VerticalReader.space)).minY])
        })
    }
}

// MARK: - Shared

struct PagePlaceholder: View {
    let number: Int
    let failed: Bool

    var body: some View {
        VStack(spacing: 14) {
            if failed {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.primary.opacity(0.5))
                Text("This page couldn't be displayed")
                    .font(.footnote)
                    .foregroundStyle(Color.primary.opacity(0.5))
            } else {
                ProgressView()
            }
            Text("\(number)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .padding(.horizontal, 24)
                .padding(.vertical, 72)
        )
    }
}

/// Shown after the last page: what you finished and what to read next.
struct EndOfComicCard: View {
    let comic: ComicBook
    let next: ComicBook?
    let openNext: (ComicBook) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Finished")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(comic.displayTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }

            if let next {
                VStack(spacing: 10) {
                    Text("UP NEXT")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    ComicCoverView(comic: next)
                        .frame(width: 118)
                    Text(next.displayTitle)
                        .font(.headline)
                }
                Button { openNext(next) } label: {
                    Label("Read Next", systemImage: "arrow.forward")
                        .font(.headline)
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }

            Button("Back to Library", action: close)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(next == nil ? .large : .regular)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.primary)
    }
}
