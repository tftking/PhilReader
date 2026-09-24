import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var appLock: AppLock
    @State private var path = NavigationPath()
    @State private var cacheSize: Int64?
    @State private var confirmClear = false

    private enum Page: String, Hashable {
        case readers, folders, acknowledgements
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    HStack(spacing: 16) {
                        AppGlyph(size: 62)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PhilReader").font(.title3.bold())
                            Text("\(library.comics.count) comics · \(library.collections.count) collections")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    NavigationLink(value: Page.readers) {
                        SettingsLabel("Readers", systemImage: "book")
                    }
                    NavigationLink(value: Page.folders) {
                        HStack {
                            SettingsLabel("Library Folders", systemImage: "icloud")
                            Spacer()
                            Text("\(library.linkedFolders.count)").foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle(isOn: Binding(get: { appLock.isEnabled },
                                         set: { value in Task { await appLock.setEnabled(value) } })) {
                        SettingsLabel("Require \(AppLock.method.name)", systemImage: AppLock.method.symbol)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Locks PhilReader whenever you leave it, and hides your library in the app switcher.")
                }

                Section("Storage") {
                    HStack {
                        SettingsLabel("Cache", systemImage: "internaldrive")
                        Spacer()
                        Text(cacheSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button { confirmClear = true } label: {
                        SettingsLabel("Clear Cache", systemImage: "trash", tint: .red)
                    }
                    .disabled(cacheSize == 0)
                }

                Section("About") {
                    NavigationLink(value: Page.acknowledgements) {
                        SettingsLabel("Acknowledgements", systemImage: "heart.text.square")
                    }
                    HStack {
                        SettingsLabel("Version", systemImage: "info.circle")
                        Spacer()
                        Text(version).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .readers: ReadersSettingsView()
                case .folders: LibraryFoldersView()
                case .acknowledgements: AcknowledgementsView()
                }
            }
            .confirmationDialog("Clear the cache?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Cache", role: .destructive) {
                    library.clearCaches()
                    Task { cacheSize = await library.cacheSize() }
                }
            } message: {
                Text("Cover thumbnails and unpacked CBR/CB7 comics are removed and rebuilt when needed. Your comics and reading progress are kept.")
            }
            .task { cacheSize = await library.cacheSize() }
            #if DEBUG
            .onAppear {
                if path.isEmpty, let page = DemoLaunch.settingsPage.flatMap(Page.init(rawValue:)) { path.append(page) }
            }
            #endif
        }
    }
}

// MARK: - Readers

/// Defaults for every comic, grouped like Panels' reader settings.
struct ReadersSettingsView: View {
    @AppStorage("reader.rightToLeft") private var rightToLeft = true
    @AppStorage("reader.mode") private var readingMode: ReadingMode = .paged
    @AppStorage("reader.background") private var background: ReaderBackground = .black
    @AppStorage("reader.tapToTurn") private var tapToTurn = true
    @AppStorage("reader.liveText") private var liveText = true
    @AppStorage("reader.fit") private var fit: PageFit = .screen
    @AppStorage("reader.spreads") private var spreadsInLandscape = true
    @AppStorage("reader.guided") private var guidedView = false
    @AppStorage("reader.transition") private var transition: PageTransition = .slide
    @AppStorage("reader.keepAwake") private var keepAwake = true
    @AppStorage("reader.showTime") private var showsReadingTime = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { transition != PageTransition.none },
                                         set: { transition = $0 ? .slide : PageTransition.none })) {
                    SettingsLabel("Page Animations", systemImage: "rectangle.stack")
                }
                Toggle(isOn: $keepAwake) {
                    SettingsLabel("Keep Display On While Reading", systemImage: "sun.max")
                }
                Toggle(isOn: $showsReadingTime) {
                    SettingsLabel("Show Reading Time", systemImage: "clock")
                }
                Toggle(isOn: $tapToTurn) {
                    SettingsLabel("Tap Edges to Turn Pages", systemImage: "hand.tap")
                }
                Toggle(isOn: $liveText) {
                    SettingsLabel("Live Text", systemImage: "text.viewfinder")
                }
                Picker(selection: $background) {
                    ForEach(ReaderBackground.allCases) { Text($0.label).tag($0) }
                } label: {
                    SettingsLabel("Background", systemImage: "circle.lefthalf.filled")
                }
            } header: {
                Text("All Readers")
            } footer: {
                Text("Live Text lets you select and look up text on a page by pressing and holding it.")
            }

            Section {
                Picker(selection: $readingMode) {
                    Text("Paginated").tag(ReadingMode.paged)
                    Text("Continuous").tag(ReadingMode.vertical)
                } label: {
                    SettingsLabel("Reading Mode", systemImage: "rectangle.portrait.on.rectangle.portrait")
                }
                Picker(selection: $rightToLeft) {
                    Text("Right to Left").tag(true)
                    Text("Left to Right").tag(false)
                } label: {
                    SettingsLabel("Direction", systemImage: "arrow.left.arrow.right")
                }
            } header: {
                Text("Reading Modes")
            } footer: {
                Text("Paginated turns one page at a time; Continuous scrolls pages as one strip, ideal for webtoons. Each comic remembers its own choice.")
            }

            Section {
                Picker(selection: $fit) {
                    ForEach(PageFit.allCases) { Text($0.label).tag($0) }
                } label: {
                    SettingsLabel("Fit Pages To", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                if transition != PageTransition.none {
                    Picker(selection: $transition) {
                        ForEach(PageTransition.allCases.filter { $0 != PageTransition.none }) { Text($0.label).tag($0) }
                    } label: {
                        SettingsLabel("Page Turn", systemImage: "arrow.right.square")
                    }
                }
                Toggle(isOn: $spreadsInLandscape) {
                    SettingsLabel("Two-Page Spreads in Landscape", systemImage: "book")
                }
                Toggle(isOn: $guidedView) {
                    SettingsLabel("Guided View", systemImage: "viewfinder")
                }
            } header: {
                Text("Paginated Reader")
            } footer: {
                Text("Guided View zooms to one panel at a time; tap the edges or use the arrow keys to move between panels.")
            }
        }
        .navigationTitle("Readers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Library folders

private struct LibraryFoldersView: View {
    @EnvironmentObject private var library: LibraryManager
    @State private var pickingFolder = false

    var body: some View {
        Form {
            Section {
                ForEach(library.linkedFolders) { folder in
                    HStack(spacing: 14) {
                        SettingsIcon(systemImage: "folder")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                            Text(folderDetail(folder))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Unlink", role: .destructive) { library.unlinkFolder(folder.id) }
                    }
                    .contextMenu {
                        Button { Task { await library.rescan(folder.id) } } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) { library.unlinkFolder(folder.id) } label: {
                            Label("Unlink Folder", systemImage: "folder.badge.minus")
                        }
                    }
                }
                Button { pickingFolder = true } label: {
                    SettingsLabel("Add Folder…", systemImage: "plus")
                }
                if !library.linkedFolders.isEmpty {
                    Button {
                        Task { await library.rescanLinkedFolders() }
                    } label: {
                        HStack {
                            SettingsLabel("Refresh Now", systemImage: "arrow.clockwise")
                            if library.isScanning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(library.isScanning)
                }
            } footer: {
                Text("Pick a folder in iCloud Drive (or anywhere in Files). PhilReader reads the comics in it without copying them, adds new ones automatically and downloads each one when you open it. Unlinking never deletes your files.")
            }
        }
        .navigationTitle("Library Folders")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await library.linkFolder(url) }
            }
        }
    }

    private func folderDetail(_ folder: LinkedFolder) -> String {
        let count = library.comicCount(in: folder)
        let comics = "\(count) \(count == 1 ? "comic" : "comics")"
        guard let scanned = folder.lastScanned else { return comics }
        guard Date().timeIntervalSince(scanned) >= 60 else { return "\(comics) · Updated just now" }
        let ago = RelativeDateTimeFormatter().localizedString(for: scanned, relativeTo: Date())
        return "\(comics) · Updated \(ago)"
    }
}

/// A settings row label with an outlined accent icon, like Panels.
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    var tint: Color? = nil

    init(_ title: String, systemImage: String, tint: Color? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(systemImage: systemImage, tint: tint)
            Text(title).foregroundStyle(tint ?? .primary)
        }
    }
}

struct SettingsIcon: View {
    let systemImage: String
    var tint: Color? = nil

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18))
            .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint))
            .frame(width: 28)
    }
}

private struct AcknowledgementsView: View {
    private let packages: [(name: String, license: String, note: String)] = [
        ("ZIPFoundation", "MIT", "Reads CBZ archives."),
        ("SWCompression", "MIT", "Reads CB7 (7-Zip) archives."),
        ("Unrar.swift", "MIT", "Reads CBR (RAR) archives."),
        ("UnRAR", "UnRAR licence",
         "UnRAR source code may be used in any software to handle RAR archives without limitations free of charge, but cannot be used to develop RAR (WinRAR) compatible archiver and to re-create RAR compression algorithm, which is proprietary."),
    ]

    var body: some View {
        List(packages, id: \.name) { package in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(package.name).font(.headline)
                    Spacer()
                    Text(package.license).font(.caption).foregroundStyle(.secondary)
                }
                Text(package.note).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Acknowledgements")
    }
}
