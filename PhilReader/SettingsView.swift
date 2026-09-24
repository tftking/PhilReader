import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var appLock: AppLock
    @AppStorage("reader.rightToLeft") private var rightToLeft = true
    @AppStorage("reader.mode") private var readingMode: ReadingMode = .paged
    @AppStorage("reader.background") private var background: ReaderBackground = .black
    @AppStorage("reader.tapToTurn") private var tapToTurn = true

    @State private var pickingFolder = false
    @State private var cacheSize: Int64?
    @State private var confirmClear = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        NavigationStack {
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

                librarySection
                readingSection

                Section {
                    Toggle(isOn: Binding(get: { appLock.isEnabled },
                                         set: { value in Task { await appLock.setEnabled(value) } })) {
                        SettingsLabel("Require \(AppLock.method.name)", systemImage: AppLock.method.symbol, color: .green)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Locks PhilReader whenever you leave it, and hides your library in the app switcher.")
                }

                Section("Storage") {
                    HStack {
                        SettingsLabel("Cache", systemImage: "internaldrive.fill", color: .gray)
                        Spacer()
                        Text(cacheSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button("Clear Cache", role: .destructive) { confirmClear = true }
                        .disabled(cacheSize == 0)
                }

                Section("About") {
                    NavigationLink {
                        AcknowledgementsView()
                    } label: {
                        SettingsLabel("Acknowledgements", systemImage: "heart.text.square.fill", color: .pink)
                    }
                    HStack {
                        SettingsLabel("Version", systemImage: "info.circle.fill", color: .blue)
                        Spacer()
                        Text(version).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    Task { await library.linkFolder(url) }
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
        }
    }

    private var librarySection: some View {
        Section {
            ForEach(library.linkedFolders) { folder in
                HStack(spacing: 12) {
                    SettingsIcon(systemImage: "folder.fill", color: .blue)
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
                SettingsLabel("Add Folder…", systemImage: "icloud.fill", color: .cyan)
            }
            if !library.linkedFolders.isEmpty {
                Button {
                    Task { await library.rescanLinkedFolders() }
                } label: {
                    HStack {
                        SettingsLabel("Refresh Now", systemImage: "arrow.clockwise", color: .indigo)
                        if library.isScanning {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(library.isScanning)
            }
        } header: {
            Text("Library Folders")
        } footer: {
            Text("Pick a folder in iCloud Drive (or anywhere in Files). PhilReader reads the comics in it without copying them, adds new ones automatically and downloads each one when you open it. Unlinking never deletes your files.")
        }
    }

    private var readingSection: some View {
        Section("Reading") {
            Picker(selection: $readingMode) {
                ForEach(ReadingMode.allCases) { Text($0.label).tag($0) }
            } label: {
                SettingsLabel("Layout", systemImage: "rectangle.portrait.on.rectangle.portrait.fill", color: .orange)
            }
            Picker(selection: $rightToLeft) {
                Text("Right to Left").tag(true)
                Text("Left to Right").tag(false)
            } label: {
                SettingsLabel("Direction", systemImage: "arrow.left.arrow.right", color: .purple)
            }
            Picker(selection: $background) {
                ForEach(ReaderBackground.allCases) { Text($0.label).tag($0) }
            } label: {
                SettingsLabel("Background", systemImage: "circle.lefthalf.filled", color: .black)
            }
            Toggle(isOn: $tapToTurn) {
                SettingsLabel("Tap Edges to Turn", systemImage: "hand.tap.fill", color: .teal)
            }
        }
    }

    private func folderDetail(_ folder: LinkedFolder) -> String {
        let count = library.comicCount(in: folder)
        let comics = "\(count) \(count == 1 ? "comic" : "comics")"
        guard let scanned = folder.lastScanned else { return comics }
        let ago = RelativeDateTimeFormatter().localizedString(for: scanned, relativeTo: Date())
        return "\(comics) · Updated \(ago)"
    }
}

/// A settings row label with a coloured rounded-square icon, like the Settings app.
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, color: color)
            Text(title).foregroundStyle(.primary)
        }
    }
}

struct SettingsIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
