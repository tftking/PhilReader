import SwiftUI

struct ReaderView: View {
    let comic: ComicBook

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ReaderModel
    @AppStorage("reader.rightToLeft") private var isRightToLeft = true
    @AppStorage("reader.tapToTurn") private var tapToTurn = true

    @State private var currentIndex: Int
    @State private var showChrome = true
    @State private var isScrubbing = false
    @State private var showSettings = false
    @State private var hideTask: Task<Void, Never>?

    init(comic: ComicBook, fileURL: URL) {
        self.comic = comic
        _model = StateObject(wrappedValue: ReaderModel(fileURL: fileURL))
        _currentIndex = State(initialValue: comic.currentPage)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.phase {
            case .opening:
                openingView
            case .failed(let message):
                failureView(message)
            case .ready:
                pager.ignoresSafeArea()
            }

            chrome
        }
        .statusBarHidden(!showChrome)
        .persistentSystemOverlays(showChrome ? .automatic : .hidden)
        .task { await openComic() }
        .onChange(of: currentIndex) { index in
            library.updateProgress(for: comic.id, page: index)
            guard !isScrubbing else { return }
            model.prefetch(around: index)
            if showChrome { setChrome(visible: false) }
        }
        .onDisappear { library.updateProgress(for: comic.id, page: currentIndex) }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(isRightToLeft: $isRightToLeft, tapToTurn: $tapToTurn)
                .presentationDetents([.medium])
                .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - Pages

    /// Pages in on-screen order. For right-to-left reading the order is
    /// reversed, so swiping right moves forward like a printed manga.
    private var displayOrder: [Int] {
        let indices = Array(0..<model.pageCount)
        return isRightToLeft ? indices.reversed() : indices
    }

    private var pager: some View {
        TabView(selection: $currentIndex) {
            ForEach(displayOrder, id: \.self) { index in
                PageView(index: index, model: model, onTap: handleTap(atFraction:))
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .id(isRightToLeft)
    }

    private var openingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(.white)
            Text("Opening \(comic.title)…")
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
        HStack(spacing: 12) {
            ChromeButton(systemImage: "chevron.backward", label: "Back") { close() }

            VStack(spacing: 2) {
                Text(comic.title)
                    .font(.headline)
                    .lineLimit(1)
                if model.pageCount > 0 {
                    Text("Page \(currentIndex + 1) of \(model.pageCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)

            ChromeButton(systemImage: "textformat.size", label: "Reader Settings") {
                showSettings = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .background(
            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if model.pageCount > 1 {
                HStack(spacing: 12) {
                    Text(isRightToLeft ? "\(model.pageCount)" : "1")
                    Slider(value: sliderValue, in: 0...Double(model.pageCount - 1), step: 1) { editing in
                        isScrubbing = editing
                        if editing {
                            hideTask?.cancel()
                        } else {
                            model.prefetch(around: currentIndex)
                            scheduleHide()
                        }
                    }
                    .tint(.white)
                    Text(isRightToLeft ? "1" : "\(model.pageCount)")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }

            HStack {
                Label(isRightToLeft ? "Right to left" : "Left to right",
                      systemImage: isRightToLeft ? "arrow.left" : "arrow.right")
                Spacer()
                Text("\(Int((progress * 100).rounded()))% read")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)
        .padding(.bottom, 12)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// The slider runs right-to-left for manga so it matches the swipe direction.
    private var sliderValue: Binding<Double> {
        Binding(
            get: {
                let index = Double(currentIndex)
                return isRightToLeft ? Double(model.pageCount - 1) - index : index
            },
            set: { value in
                let position = Int(value.rounded())
                currentIndex = isRightToLeft ? model.pageCount - 1 - position : position
            }
        )
    }

    private var progress: Double {
        guard model.pageCount > 1 else { return 1 }
        return Double(currentIndex) / Double(model.pageCount - 1)
    }

    // MARK: - Actions

    private func openComic() async {
        await model.open()
        guard model.phase == .ready else { return }
        currentIndex = min(max(currentIndex, 0), model.pageCount - 1)
        model.prefetch(around: currentIndex)
        #if DEBUG
        if DemoLaunch.chrome == "hidden" { showChrome = false; return }
        #endif
        scheduleHide()
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
        let step = towardLeft != isRightToLeft ? -1 : 1
        let target = currentIndex + step
        guard (0..<model.pageCount).contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { currentIndex = target }
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
            guard !Task.isCancelled, !showSettings, !isScrubbing else { return }
            withAnimation(.easeOut(duration: 0.3)) { showChrome = false }
        }
    }

    private func close() {
        library.updateProgress(for: comic.id, page: currentIndex)
        dismiss()
    }
}

// MARK: - Page

private struct PageView: View {
    let index: Int
    let model: ReaderModel
    let onTap: (CGFloat) -> Void

    @State private var image: UIImage?
    @State private var failed = false

    init(index: Int, model: ReaderModel, onTap: @escaping (CGFloat) -> Void) {
        self.index = index
        self.model = model
        self.onTap = onTap
        _image = State(initialValue: model.cachedImage(at: index))
    }

    var body: some View {
        ZStack {
            if let image {
                ZoomablePage(image: image, onTap: onTap)
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

private struct PagePlaceholder: View {
    let number: Int
    let failed: Bool

    var body: some View {
        VStack(spacing: 14) {
            if failed {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.5))
                Text("This page couldn't be displayed")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ProgressView().tint(.white.opacity(0.7))
            }
            Text("\(number)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.04))
                .padding(.horizontal, 24)
                .padding(.vertical, 72)
        )
    }
}

private struct ChromeButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Settings

struct ReaderSettingsSheet: View {
    @Binding var isRightToLeft: Bool
    @Binding var tapToTurn: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reading Direction", selection: $isRightToLeft) {
                        Text("Right to Left").tag(true)
                        Text("Left to Right").tag(false)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Reading Direction")
                } footer: {
                    Text("Right to left is the traditional layout for manga.")
                }

                Section {
                    Toggle("Tap Edges to Turn Pages", isOn: $tapToTurn)
                } footer: {
                    Text("Tap the middle of a page to show or hide the controls. Double-tap or pinch to zoom.")
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
