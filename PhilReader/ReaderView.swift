import SwiftUI

struct ReaderView: View {
    let comic: ComicBook
    var openNext: (ComicBook) -> Void = { _ in }

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ReaderModel
    @AppStorage("reader.rightToLeft") private var defaultRightToLeft = true
    @AppStorage("reader.mode") private var defaultMode: ReadingMode = .paged
    @AppStorage("reader.background") private var background: ReaderBackground = .black
    @AppStorage("reader.tapToTurn") private var tapToTurn = true
    @AppStorage("reader.liveText") private var liveText = true
    @AppStorage("reader.fit") private var fit: PageFit = .screen
    @AppStorage("reader.spreads") private var spreadsInLandscape = true
    @AppStorage("reader.guided") private var guidedView = false
    @AppStorage("reader.transition") private var transition: PageTransition = .slide
    @AppStorage("reader.keepAwake") private var keepAwake = true

    /// Zero-based page; `pageCount` means the end-of-comic card.
    @State private var currentIndex: Int
    @State private var jumpToken = 0
    @State private var showChrome = true
    @State private var isScrubbing = false
    @State private var showSettings = false
    @State private var showPages = false
    @State private var hideTask: Task<Void, Never>?
    @State private var containerSize: CGSize = .zero
    /// Guided view: detected panels for `panelsPage`, and which one is shown.
    @State private var panels: [CGRect] = []
    @State private var panelsPage = -1
    @State private var panelIndex = 0
    /// Panel to show after a guided step moves to another page (`Int.max` = last).
    @State private var pendingPanelIndex: Int?

    init(comic: ComicBook, fileURL: URL, openNext: @escaping (ComicBook) -> Void = { _ in }) {
        self.comic = comic
        self.openNext = openNext
        _model = StateObject(wrappedValue: ReaderModel(fileURL: fileURL))
        _currentIndex = State(initialValue: comic.currentPage)
    }

    // MARK: - Derived state

    private var liveComic: ComicBook { library.comic(withID: comic.id) ?? comic }
    private var mode: ReadingMode { liveComic.readingMode ?? defaultMode }
    private var isRightToLeft: Bool {
        liveComic.readsRightToLeft ?? liveComic.metadata?.readsRightToLeft ?? defaultRightToLeft
    }
    /// The slider follows the swipe direction: reversed only for right-to-left paging.
    private var sliderReversed: Bool { mode == .paged && isRightToLeft }
    private var pageIndex: Int { min(currentIndex, max(model.pageCount - 1, 0)) }
    private var isAtEnd: Bool { model.pageCount > 0 && currentIndex >= model.pageCount }
    private var isBookmarked: Bool { liveComic.bookmarks.contains(pageIndex) }
    private var isGuided: Bool { guidedView && mode == .paged }
    private var showsSpreads: Bool {
        mode == .paged && !isGuided && spreadsInLandscape && containerSize.width > containerSize.height
    }

    /// The panel guided view is zoomed to on the current page, if known.
    private var focus: (page: Int, rect: CGRect)? {
        guard isGuided, panelsPage == currentIndex, !panels.isEmpty else { return nil }
        return (currentIndex, panels[min(panelIndex, panels.count - 1)])
    }

    /// Page groups in reading order (single pages or spreads), then the end card.
    private var groups: [[Int]] {
        let pages = showsSpreads
            ? SpreadLayout.spreads(pageCount: model.pageCount, isWide: model.isWidePage)
            : (0..<model.pageCount).map { [$0] }
        return pages + [[model.pageCount]]
    }

    var body: some View {
        ZStack {
            background.color.ignoresSafeArea()

            switch model.phase {
            case .downloading, .opening:
                openingView
            case .failed(let message):
                failureView(message)
            case .ready:
                pages
                    .ignoresSafeArea()
                    .environment(\.colorScheme, background.colorScheme)
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { containerSize = proxy.size }
                            .onChange(of: proxy.size) { containerSize = $0 }
                    })
            }

            chrome
            keyboardShortcuts
        }
        .statusBarHidden(!showChrome)
        .persistentSystemOverlays(showChrome ? .automatic : .hidden)
        .task { await openComic() }
        .task(id: "\(currentIndex)-\(isGuided)-\(isRightToLeft)-\(model.pageCount)") { await loadPanels() }
        .onChange(of: currentIndex) { index in
            panelIndex = pendingPanelIndex ?? 0
            pendingPanelIndex = nil
            library.updateProgress(for: comic.id, page: index)
            guard !isScrubbing else { return }
            model.prefetch(around: index)
            var keepsChrome = showPages || showSettings
            #if DEBUG
            keepsChrome = keepsChrome || DemoLaunch.chrome == "visible"
            #endif
            if showChrome && !keepsChrome { setChrome(visible: false) }
        }
        .onChange(of: mode) { newMode in
            model.sizesForVerticalScroll = newMode == .vertical
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            library.updateProgress(for: comic.id, page: pageIndex)
        }
        .sheet(isPresented: $showSettings, onDismiss: scheduleHide) {
            ReaderSettingsSheet(mode: modeBinding, isRightToLeft: directionBinding, guidedView: $guidedView,
                                transition: $transition, fit: $fit,
                                spreadsInLandscape: $spreadsInLandscape, background: $background,
                                tapToTurn: $tapToTurn, liveText: $liveText)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPages, onDismiss: scheduleHide) {
            PageBrowserView(model: model, currentIndex: pageIndex, bookmarks: liveComic.bookmarks) { index in
                jump(to: index, animated: false)
            }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private var pages: some View {
        let end = EndOfComicCard(comic: liveComic,
                                 next: LibraryQuery.nextIssue(after: liveComic, in: library.comics),
                                 openNext: { next in
                                     close()
                                     openNext(next)
                                 },
                                 close: close)
        switch mode {
        case .paged:
            PagedReader(model: model, currentIndex: $currentIndex, groups: groups, isRightToLeft: isRightToLeft,
                        fit: fit, focus: focus, liveText: liveText, transition: transition,
                        onTap: handleTap(atFraction:),
                        onSwipe: { fingerMovedLeft in turnPage(towardLeft: !fingerMovedLeft) }, end: end)
        case .vertical:
            VerticalReader(model: model, currentIndex: $currentIndex, jumpToken: jumpToken,
                           onTap: { setChrome(visible: !showChrome) }, end: end)
        }
    }

    private var openingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(.white)
            Text(model.phase == .downloading ? "Downloading from iCloud…" : "Opening \(comic.displayTitle)…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Couldn't open this comic")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Back to Library") { close() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if model.phase == .ready { bottomBar }
        }
        .foregroundStyle(.white)
        .opacity(showChrome ? 1 : 0)
        .allowsHitTesting(showChrome)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ChromeButton(systemImage: "chevron.backward", label: "Back") { close() }

            VStack(spacing: 2) {
                Text(comic.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if model.pageCount > 0 {
                    Text(isAtEnd ? "Finished" : pageDescription)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)

            if model.phase == .ready {
                ChromeButton(systemImage: isBookmarked ? "bookmark.fill" : "bookmark",
                             label: isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                             tint: isBookmarked ? .accentColor : .white) {
                    library.toggleBookmark(comic.id, page: pageIndex)
                    scheduleHide()
                }
                .disabled(isAtEnd)
            }
            ChromeButton(systemImage: "textformat.size", label: "Reader Settings") {
                hideTask?.cancel()
                showSettings = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .background(ChromeBackground(edge: .top))
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if model.pageCount > 1 {
                HStack(spacing: 12) {
                    Text(sliderReversed ? "\(model.pageCount)" : "1")
                    Slider(value: sliderValue, in: 0...Double(model.pageCount - 1), step: 1) { editing in
                        isScrubbing = editing
                        if editing {
                            hideTask?.cancel()
                        } else {
                            model.prefetch(around: currentIndex)
                            jumpToken += 1
                            scheduleHide()
                        }
                    }
                    .tint(.white)
                    Text(sliderReversed ? "1" : "\(model.pageCount)")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }

            HStack(spacing: 12) {
                ChromeButton(systemImage: "square.grid.2x2", label: "All Pages", size: 36) {
                    hideTask?.cancel()
                    showPages = true
                }
                if mode == .paged {
                    ChromeButton(systemImage: "viewfinder", label: isGuided ? "Turn Off Guided View" : "Guided View",
                                 tint: isGuided ? .accentColor : .white, size: 36) {
                        withAnimation(.easeInOut(duration: 0.25)) { guidedView.toggle() }
                        scheduleHide()
                    }
                }
                Label(modeDescription, systemImage: modeIcon)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(Int((liveComic.progress * 100).rounded()))% read")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)
        .padding(.bottom, 12)
        .background(ChromeBackground(edge: .bottom))
    }

    private var modeDescription: String {
        switch mode {
        case .vertical: return "Vertical scroll"
        case .paged: return isRightToLeft ? "Right to left" : "Left to right"
        }
    }

    private var modeIcon: String {
        switch mode {
        case .vertical: return "arrow.down"
        case .paged: return isRightToLeft ? "arrow.left" : "arrow.right"
        }
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: {
                let index = Double(pageIndex)
                return sliderReversed ? Double(model.pageCount - 1) - index : index
            },
            set: { value in
                let position = Int(value.rounded())
                currentIndex = sliderReversed ? model.pageCount - 1 - position : position
            }
        )
    }

    private var modeBinding: Binding<ReadingMode> {
        Binding(get: { mode }, set: { newMode in
            library.setReadingMode(comic.id, newMode)
            defaultMode = newMode
            jumpToken += 1
        })
    }

    private var directionBinding: Binding<Bool> {
        Binding(get: { isRightToLeft }, set: { rightToLeft in
            library.setDirection(comic.id, rightToLeft: rightToLeft)
            defaultRightToLeft = rightToLeft
        })
    }

    /// Hidden buttons that give hardware keyboards arrow-key and space-bar page turns.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Previous Page") { turnPage(towardLeft: true) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next Page") { turnPage(towardLeft: false) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Forward") { step(1) }
                .keyboardShortcut(.space, modifiers: [])
            Button("Back") { step(-1) }
                .keyboardShortcut(.space, modifiers: .shift)
            Button("Close") { close() }
                .keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func openComic() async {
        library.markOpened(comic.id)
        model.sizesForVerticalScroll = mode == .vertical
        await model.open()
        guard model.phase == .ready else { return }
        library.didOpen(comic.id, pageCount: model.pageCount)
        currentIndex = min(max(currentIndex, 0), model.pageCount - 1)
        model.prefetch(around: currentIndex)
        #if DEBUG
        if DemoLaunch.showsEnd { currentIndex = model.pageCount; jumpToken += 1 }
        switch DemoLaunch.sheet {
        case "pages": showPages = true; return
        case "settings": showSettings = true; return
        default: break
        }
        if DemoLaunch.chrome == "hidden" { showChrome = false; return }
        #endif
        scheduleHide()
    }

    private var pageDescription: String {
        let page = "Page \(pageIndex + 1) of \(model.pageCount)"
        guard focus != nil, panels.count > 1 else { return page }
        return "\(page) · Panel \(min(panelIndex, panels.count - 1) + 1) of \(panels.count)"
    }

    private func loadPanels() async {
        guard isGuided, model.phase == .ready, currentIndex < model.pageCount else {
            panels = []
            panelsPage = -1
            return
        }
        let page = currentIndex
        let found = await model.panels(at: page, rightToLeft: isRightToLeft)
        guard page == currentIndex else { return }
        panels = found
        panelsPage = page
        if panelIndex == .max { panelIndex = max(found.count - 1, 0) }
    }

    /// Guided view: the next or previous panel, moving to the neighbouring
    /// page (at its first or last panel) past either end.
    private func stepPanel(_ delta: Int) {
        let target = panelIndex + delta
        if panelsPage == currentIndex, panels.indices.contains(target) {
            panelIndex = target
            return
        }
        pendingPanelIndex = delta > 0 ? 0 : .max
        step(delta)
        if pendingPanelIndex != nil && currentIndex == panelsPage {
            // Couldn't move (first or last page).
            pendingPanelIndex = nil
        }
    }

    private func handleTap(atFraction x: CGFloat) {
        guard tapToTurn else { return setChrome(visible: !showChrome) }
        if x < 0.3 {
            turnPage(towardLeft: true)
        } else if x > 0.7 {
            turnPage(towardLeft: false)
        } else {
            setChrome(visible: !showChrome)
        }
    }

    private func turnPage(towardLeft: Bool) {
        // The left edge goes back in left-to-right reading and forward in manga.
        let forward = mode == .paged && isRightToLeft ? towardLeft : !towardLeft
        if isGuided && currentIndex < model.pageCount {
            stepPanel(forward ? 1 : -1)
        } else {
            step(forward ? 1 : -1)
        }
    }

    /// Moves by `delta` pages (or spreads), including onto the end-of-comic card.
    private func step(_ delta: Int) {
        guard model.phase == .ready else { return }
        if mode == .paged {
            let groups = groups
            guard let current = groups.firstIndex(where: { $0.contains(currentIndex) }),
                  groups.indices.contains(current + delta) else { return }
            jump(to: groups[current + delta][0], animated: true)
        } else {
            let target = currentIndex + delta
            guard (0...model.pageCount).contains(target) else { return }
            jump(to: target, animated: true)
        }
    }

    private func jump(to index: Int, animated: Bool) {
        if animated && mode == .paged && transition != .none {
            withAnimation(.easeInOut(duration: transition == .fade ? 0.2 : 0.25)) { currentIndex = index }
        } else {
            currentIndex = index
        }
        jumpToken += 1
    }

    private func setChrome(visible: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) { showChrome = visible }
        if visible { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        #if DEBUG
        if DemoLaunch.chrome == "visible" { return }
        #endif
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, !showSettings, !showPages, !isScrubbing else { return }
            withAnimation(.easeOut(duration: 0.3)) { showChrome = false }
        }
    }

    private func close() {
        library.updateProgress(for: comic.id, page: pageIndex)
        dismiss()
    }
}

/// Frosted glass behind the reader's top and bottom bars, fading out toward the
/// page, so the controls stay legible over white pages as well as black ones.
private struct ChromeBackground: View {
    let edge: VerticalEdge

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.35))
            .environment(\.colorScheme, .dark)
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.65),
                                       .init(color: .clear, location: 1)],
                               startPoint: edge == .top ? .top : .bottom,
                               endPoint: edge == .top ? .bottom : .top)
            )
            .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
    }
}

private struct ChromeButton: View {
    let systemImage: String
    let label: String
    var tint: Color = .white
    var size: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
