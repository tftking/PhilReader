import SwiftUI

// MARK: - Paged

/// One page or two-page spread at a time, swiped horizontally. The final
/// group is the end card.
struct PagedReader: View {
    @ObservedObject var model: ReaderModel
    @Binding var currentIndex: Int
    /// Page groups in reading order: single pages or spreads, then `[pageCount]` for the end card.
    let groups: [[Int]]
    let isRightToLeft: Bool
    let fit: PageFit
    /// Guided view: the panel to zoom to on one page.
    var focus: (page: Int, rect: CGRect)? = nil
    let liveText: Bool
    var transition: PageTransition = .slide
    let onTap: (CGFloat) -> Void
    /// Fade / no-animation modes: a horizontal swipe, `true` when the finger moved left.
    var onSwipe: (Bool) -> Void = { _ in }
    let end: EndOfComicCard

    @Environment(\.pageFilters) private var filters

    /// Groups in on-screen order. For right-to-left reading the order is
    /// reversed, so swiping right moves forward like a printed manga.
    private var displayGroups: [[Int]] {
        isRightToLeft ? groups.reversed() : groups
    }

    /// Selection is the first page of the visible group.
    private var selection: Binding<Int> {
        Binding(
            get: { groups.first(where: { $0.contains(currentIndex) })?.first ?? currentIndex },
            set: { currentIndex = $0 }
        )
    }

    var body: some View {
        switch transition {
        case .slide:
            TabView(selection: selection) {
                ForEach(displayGroups, id: \.self) { group in
                    groupView(group).tag(group[0])
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .id("\(isRightToLeft)-\(groups.count)")
        case .fade, .none:
            // One group at a time; page changes cross-fade (or cut) instead of sliding.
            let group = groups.first(where: { $0.contains(currentIndex) }) ?? [currentIndex]
            ZStack {
                groupView(group)
                    .id(group)
                    .transition(transition == .fade ? .opacity : .identity)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { drag in
                    let dx = drag.translation.width
                    guard abs(dx) > 60, abs(dx) > abs(drag.translation.height) * 1.5 else { return }
                    onSwipe(dx < 0)
                }
            )
        }
    }

    @ViewBuilder
    private func groupView(_ group: [Int]) -> some View {
        if group == [model.pageCount] {
            end
        } else if group.count == 2 {
            // A spread is drawn left to right, so manga puts the later page on the left.
            SpreadView(pages: isRightToLeft ? group.reversed() : group, model: model,
                       fit: fit, liveText: liveText, onTap: onTap)
                .pageFilters(filters)
        } else {
            PageView(index: group[0], model: model, fit: fit,
                     focusRect: focus?.page == group[0] ? focus?.rect : nil,
                     liveText: liveText, onTap: onTap)
                .pageFilters(filters)
        }
    }
}

private struct PageView: View {
    let index: Int
    let model: ReaderModel
    let fit: PageFit
    let focusRect: CGRect?
    let liveText: Bool
    let onTap: (CGFloat) -> Void

    @State private var image: UIImage?
    @State private var failed = false

    init(index: Int, model: ReaderModel, fit: PageFit, focusRect: CGRect?, liveText: Bool,
         onTap: @escaping (CGFloat) -> Void) {
        self.index = index
        self.model = model
        self.fit = fit
        self.focusRect = focusRect
        self.liveText = liveText
        self.onTap = onTap
        _image = State(initialValue: model.cachedImage(at: index))
    }

    var body: some View {
        ZStack {
            if let image {
                ZoomablePage(image: image, fit: fit, focusRect: focusRect, liveText: liveText, onTap: onTap)
                    .transition(.opacity)
            } else {
                TappablePlaceholder(number: index + 1, failed: failed, onTap: onTap)
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

/// Two pages side by side, joined into one image so they zoom together.
private struct SpreadView: View {
    /// Page indices in on-screen, left-to-right order.
    let pages: [Int]
    let model: ReaderModel
    let fit: PageFit
    let liveText: Bool
    let onTap: (CGFloat) -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                ZoomablePage(image: image, fit: fit, liveText: liveText, onTap: onTap)
                    .transition(.opacity)
            } else {
                TappablePlaceholder(number: (pages.min() ?? 0) + 1, failed: failed, onTap: onTap)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .task(id: pages) {
            async let leftPage = model.image(at: pages[0])
            async let rightPage = model.image(at: pages[1])
            let (left, right) = await (leftPage, rightPage)
            let joined: UIImage?
            if let left, let right {
                joined = SpreadLayout.composite(left: left, right: right)
            } else {
                joined = left ?? right
            }
            withAnimation(.easeOut(duration: 0.25)) {
                image = joined
                failed = joined == nil
            }
        }
    }
}

private struct TappablePlaceholder: View {
    let number: Int
    let failed: Bool
    let onTap: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            PagePlaceholder(number: number, failed: failed)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    onTap(tap.location.x / max(proxy.size.width, 1))
                })
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

    /// True until the opening scroll to the saved page has landed, and during
    /// programmatic jumps, so the scroll tracker doesn't overwrite the page.
    @State private var isJumping = true
    @Environment(\.doubleTapScale) private var doubleTapScale
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var pan: CGFloat = 0
    @State private var basePan: CGFloat = 0

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
                    let target = currentIndex
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .top)
                        // Lazy pages above may resize as they load; land once more, then start tracking.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            proxy.scrollTo(target, anchor: .top)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isJumping = false }
                        }
                    }
                }
                .onChange(of: jumpToken) { _ in
                    isJumping = true
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(currentIndex, anchor: .top) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isJumping = false }
                }
            }
            // Zoom scales the whole strip (so pages stay lazily loaded) and pans it sideways.
            .scaleEffect(scale)
            .offset(x: pan)
            .frame(width: outer.size.width, height: outer.size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = VerticalZoom.clampedScale(baseScale * value)
                        pan = VerticalZoom.clampedPan(basePan, scale: scale, width: outer.size.width)
                    }
                    .onEnded { _ in
                        if scale < 1.05 { resetZoom() } else {
                            baseScale = scale
                            basePan = pan
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { drag in
                        guard scale > 1 else { return }
                        pan = VerticalZoom.clampedPan(basePan + drag.translation.width, scale: scale, width: outer.size.width)
                    }
                    .onEnded { _ in basePan = pan }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if scale > 1 {
                        resetZoom()
                    } else if let doubleTapScale {
                        scale = VerticalZoom.clampedScale(doubleTapScale)
                        baseScale = scale
                    }
                }
            }
            .onTapGesture { onTap() }
        }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            scale = 1
            baseScale = 1
            pan = 0
            basePan = 0
        }
    }

    static let space = "verticalReader"
}

private struct VerticalPage: View {
    let index: Int
    let model: ReaderModel
    let width: CGFloat

    @Environment(\.pageFilters) private var filters
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
                    .pageFilters(filters)
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
                    .font(.system(.title2, design: .rounded).bold())
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
