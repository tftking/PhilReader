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
    @AppStorage("reader.showTime") private var showsReadingTime = true
    @AppStorage(ReaderKeys.leftTap) private var leftTap: EdgeTapAction = .turnTowardSide
    @AppStorage(ReaderKeys.rightTap) private var rightTap: EdgeTapAction = .turnTowardSide
    @AppStorage(ReaderKeys.tapZone) private var tapZone: TapZoneSize = .medium
    @AppStorage(ReaderKeys.doubleTapZoom) private var doubleTapZoom: DoubleTapZoom = .medium
    @AppStorage(ReaderKeys.dragToClose) private var dragToClose = true
    @AppStorage(ReaderKeys.avoidMargins) private var avoidMargins = false
    @AppStorage(ReaderKeys.filters) private var filters = StoredFilters()
    @AppStorage(ReaderKeys.filtersEnabled) private var filtersEnabled = false
    @AppStorage(ReaderKeys.presets) private var customPresets = PresetList()
    @Environment(\.scenePhase) private var scenePhase
    /// When the current stretch of reading started; `nil` while the app is in the background.
    @State private var sessionStart: Date? = Date()
    @State private var showFilters = false
    @State private var settingsDetent: PresentationDetent = .medium

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

    /// Pages fill the screen unless Avoid Device Margins is on.
    private var pageEdgesIgnoringSafeArea: Edge.Set { avoidMargins ? [] : .all }
    private var activeFilters: ImageFilterSettings? { filtersEnabled ? filters.value : nil }
    private var pullToCloseAction: (() -> Void)? {
        guard dragToClose else { return nil }
        return { close() }
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
                    .ignoresSafeArea(edges: pageEdgesIgnoringSafeArea)
                    .environment(\.colorScheme, background.colorScheme)
                    .environment(\.pageFilters, activeFilters)
                    .environment(\.doubleTapScale, doubleTapZoom.scale)
                    .environment(\.pullToClose, pullToCloseAction)
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
        .onChange(of: keepAwake) { UIApplication.shared.isIdleTimerDisabled = $0 }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            library.updateProgress(for: comic.id, page: pageIndex)
            recordReadingTime()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                if sessionStart == nil { sessionStart = Date() }
            } else {
                recordReadingTime()
            }
        }
        .sheet(isPresented: $showFilters, onDismiss: scheduleHide) {
            NavigationStack {
                ImageFiltersView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showFilters = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings, onDismiss: scheduleHide) {
            ReaderSettingsSheet(mode: modeBinding, isRightToLeft: directionBinding, guidedView: $guidedView,
                                transition: $transition, fit: $fit,
                                spreadsInLandscape: $spreadsInLandscape, background: $background,
                                tapToTurn: $tapToTurn, liveText: $liveText)
                .presentationDetents([.medium, .large], selection: $settingsDetent)
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
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if model.phase == .ready { bottomBar }
            }
            if isScrubbing && model.pageCount > 1 {
                ScrubPreviewStrip(model: model, index: pageIndex)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isScrubbing)
        .foregroundStyle(.white)
        .opacity(showChrome ? 1 : 0)
        .allowsHitTesting(showChrome)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ChromeButton(systemImage: "xmark", label: "Close") { close() }

            Menu {
                if model.pageCount > 0 {
                    Text(isAtEnd ? "Finished" : pageDescription)
                }
                Picker("Layout", selection: modeBinding) {
                    Label("Paginated", systemImage: "book").tag(ReadingMode.paged)
                    Label("Continuous", systemImage: "arrow.down").tag(ReadingMode.vertical)
                }
                if mode == .paged {
                    Picker("Direction", selection: directionBinding) {
                        Label("Right to Left", systemImage: "arrow.left").tag(true)
                        Label("Left to Right", systemImage: "arrow.right").tag(false)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(comic.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.25), in: Circle())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
            .simultaneousGesture(TapGesture().onEnded { hideTask?.cancel() })
            .disabled(model.phase != .ready)

            Menu {
                Button { hideTask?.cancel(); showSettings = true } label: {
                    Label("Reader Settings", systemImage: "textformat.size")
                }
                if model.phase == .ready {
                    Button { hideTask?.cancel(); showPages = true } label: {
                        Label("All Pages", systemImage: "square.grid.2x2")
                    }
                    if !isAtEnd {
                        Button {
                            library.toggleBookmark(comic.id, page: pageIndex)
                            scheduleHide()
                        } label: {
                            isBookmarked ? Label("Remove Bookmark", systemImage: "bookmark.slash")
                                         : Label("Bookmark Page", systemImage: "bookmark")
                        }
                    }
                    if mode == .paged {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { guidedView.toggle() }
                            scheduleHide()
                        } label: {
                            isGuided ? Label("Turn Off Guided View", systemImage: "viewfinder")
                                     : Label("Guided View", systemImage: "viewfinder")
                        }
                    }
                    Button { hideTask?.cancel(); showFilters = true } label: {
                        Label("Image Filters", systemImage: "camera.filters")
                    }
                    Menu {
                        ForEach(ReaderPreset.builtIn + customPresets.items) { preset in
                            Button(preset.name) { apply(preset) }
                        }
                    } label: {
                        Label("Presets", systemImage: "slider.horizontal.3")
                    }
                }
            } label: {
                ChromeCircle(systemImage: "ellipsis")
            }
            .simultaneousGesture(TapGesture().onEnded { hideTask?.cancel() })
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(ChromeBackground(edge: .top))
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if model.pageCount > 1 {
                PageScrubber(value: sliderValue, count: model.pageCount, reversed: sliderReversed) { editing in
                    isScrubbing = editing
                    if editing {
                        hideTask?.cancel()
                    } else {
                        model.prefetch(around: currentIndex)
                        jumpToken += 1
                        scheduleHide()
                    }
                }
            }
            HStack {
                if showsReadingTime {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text("Time reading: \(Self.duration(readingTime(at: context.date)))")
                    }
                }
                Spacer()
                if liveComic.bookmarks.contains(pageIndex) && !isAtEnd {
                    Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor)
                }
                Text(isAtEnd ? "Finished" : "Page: \(pageIndex + 1) of \(model.pageCount)")
            }
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    /// Time spent reading this comic so far, including the current session.
    private func readingTime(at date: Date) -> TimeInterval {
        liveComic.readingTime + (sessionStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    /// Adds the current stretch of reading to the comic's total.
    private func recordReadingTime() {
        guard let start = sessionStart else { return }
        sessionStart = nil
        library.addReadingTime(comic.id, seconds: Date().timeIntervalSince(start))
    }

    /// "4:05" or "1:02:09".
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval), 0)
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
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
        case "settings-full":
            settingsDetent = .large
            showSettings = true
            return
        default: break
        }
        if DemoLaunch.chrome == "hidden" { showChrome = false; return }
        if DemoLaunch.scrubs { isScrubbing = true }
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
        switch TapZones.outcome(atFraction: x, zone: tapZone.fraction, left: leftTap, right: rightTap,
                                rightToLeft: mode == .paged && isRightToLeft) {
        case .forward: advance(by: 1)
        case .backward: advance(by: -1)
        case .toggleControls: setChrome(visible: !showChrome)
        case .nothing: break
        }
    }

    /// Moves forward or back a panel in guided view, otherwise a page.
    private func advance(by delta: Int) {
        if isGuided && currentIndex < model.pageCount {
            stepPanel(delta)
        } else {
            step(delta)
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

    private func apply(_ preset: ReaderPreset) {
        preset.apply()
        library.setReadingMode(comic.id, preset.mode)
        library.setDirection(comic.id, rightToLeft: preset.rightToLeft)
        model.sizesForVerticalScroll = preset.mode == .vertical
        jumpToken += 1
        scheduleHide()
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChromeCircle(systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A round frosted button face, like the glass buttons in Panels.
private struct ChromeCircle: View {
    let systemImage: String
    var tint: Color = .white

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.12)))
            .environment(\.colorScheme, .dark)
    }
}

/// A thin progress track you can drag along to move through the comic.
private struct PageScrubber: View {
    @Binding var value: Double
    let count: Int
    let reversed: Bool
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    init(value: Binding<Double>, count: Int, reversed: Bool, onEditingChanged: @escaping (Bool) -> Void) {
        _value = value
        self.count = count
        self.reversed = reversed
        self.onEditingChanged = onEditingChanged
    }

    private var fraction: CGFloat {
        count > 1 ? CGFloat(value) / CGFloat(count - 1) : 0
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: reversed ? .trailing : .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white)
                    .frame(width: max(width * (reversed ? 1 - fraction : fraction), 6))
            }
            .frame(height: isDragging ? 8 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let position = min(max(drag.location.x / max(width, 1), 0), 1)
                        let newValue = (position * CGFloat(count - 1)).rounded()
                        if Double(newValue) != value { value = Double(newValue) }
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Page")
        .accessibilityValue("\(Int(value) + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, Double(count - 1))
            case .decrement: value = max(value - 1, 0)
            @unknown default: break
            }
        }
    }
}

/// Thumbnails of the pages around the one you're scrubbing to, down the side of the screen.
private struct ScrubPreviewStrip: View {
    let model: ReaderModel
    let index: Int

    private var indices: [Int] {
        Array(max(index - 2, 0)...min(index + 2, model.pageCount - 1))
    }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(indices, id: \.self) { page in
                ScrubThumbnail(model: model, index: page, isCurrent: page == index)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.12), value: index)
    }
}

private struct ScrubThumbnail: View {
    let model: ReaderModel
    let index: Int
    let isCurrent: Bool

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            Color.white.opacity(0.1)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.white.opacity(isCurrent ? 0.9 : 0.15), lineWidth: isCurrent ? 2 : 0.5))
                .shadow(color: .black.opacity(0.4), radius: isCurrent ? 10 : 3, y: 3)
            if !isCurrent {
                Text("\(index + 1)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: isCurrent ? 96 : 64)
        .task(id: index) {
            image = await model.thumbnail(at: index)
        }
    }
}
