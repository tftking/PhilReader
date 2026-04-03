import SwiftUI

struct ReaderView: View {
    let comic: ComicBook

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss

    @State private var pages: [UIImage] = []
    @State private var currentIndex: Int = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showUI = true
    @State private var isRightToLeft = false
    @State private var showSettings = false

    // Auto-hide UI timer
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else {
                readerContent
            }

            if showUI {
                overlayUI
            }
        }
        .statusBar(hidden: !showUI)
        .ignoresSafeArea()
        .task { await loadPages() }
        .onDisappear {
            library.updateProgress(for: comic.id, page: currentIndex)
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(isRightToLeft: $isRightToLeft)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Reader Content

    private var readerContent: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, image in
                ZoomableImageView(image: image)
                    .tag(index)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showUI.toggle()
                        }
                        if showUI { scheduleHideUI() }
                    }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
        .onChange(of: currentIndex) { newValue in
            library.updateProgress(for: comic.id, page: newValue)
        }
        .onAppear {
            currentIndex = comic.currentPage
            scheduleHideUI()
        }
    }

    // MARK: - Overlay UI

    private var overlayUI: some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    library.updateProgress(for: comic.id, page: currentIndex)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Spacer()

                Text(comic.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)

                Spacer()

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)

            Spacer()

            // Bottom bar
            VStack(spacing: 8) {
                if pages.count > 1 {
                    pageSlider
                }
                HStack {
                    Text(pages.isEmpty ? "" : "Page \(currentIndex + 1) of \(pages.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    if isRightToLeft {
                        Label("R→L", systemImage: "arrow.left")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .foregroundStyle(.white)
    }

    private var pageSlider: some View {
        HStack(spacing: 12) {
            Text("1")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Slider(
                value: Binding(
                    get: { Double(currentIndex) },
                    set: { currentIndex = Int($0.rounded()) }
                ),
                in: 0...Double(max(pages.count - 1, 1)),
                step: 1
            )
            .tint(.white)
            Text("\(pages.count)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(.white)
            Text("Loading pages…")
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Could not open comic")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Go Back") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }

    // MARK: - Helpers

    private func loadPages() async {
        isLoading = true
        do {
            let url = library.fileURL(for: comic)
            let rawPages = try await CBZService.shared.extractAllPages(from: url)
            pages = rawPages.compactMap { UIImage(data: $0) }
            currentIndex = min(comic.currentPage, max(0, pages.count - 1))
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func scheduleHideUI() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) { showUI = false }
            }
        }
    }
}

// MARK: - Zoomable Image

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        // Double-tap to zoom
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        layoutImageView(in: scrollView, imageView: context.coordinator.imageView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func layoutImageView(in scrollView: UIScrollView, imageView: UIImageView?) {
        guard let imageView else { return }
        let bounds = scrollView.bounds
        imageView.frame = bounds
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let offsetX = max((scrollView.bounds.width - imageView.frame.width) / 2, 0)
            let offsetY = max((scrollView.bounds.height - imageView.frame.height) / 2, 0)
            imageView.center = CGPoint(
                x: imageView.frame.width / 2 + offsetX,
                y: imageView.frame.height / 2 + offsetY
            )
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let rect = CGRect(x: point.x - 60, y: point.y - 90, width: 120, height: 180)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

// MARK: - Settings Sheet

struct ReaderSettingsSheet: View {
    @Binding var isRightToLeft: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading Direction") {
                    Toggle("Right to Left (Manga)", isOn: $isRightToLeft)
                }
                Section {
                    Text("PhilReader v1.0")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
