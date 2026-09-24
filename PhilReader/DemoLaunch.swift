#if DEBUG
import Foundation

/// Debug-only launch arguments that put the app into a known state, used by
/// CI to capture simulator screenshots. For example:
///
///     xcrun simctl launch booted com.philreader.app -demoLibrary YES \
///         -demoProgress "Starfall 1=4;Midnight Ramen 1=12" \
///         -demoOpen "Starfall 1" -demoPage 3 -demoChrome visible
///
/// Comics are referred to by file name without extension.
enum DemoLaunch {
    private static var defaults: UserDefaults { .standard }

    /// Import every `.cbz` placed in the app's Documents folder.
    static var importsLibrary: Bool { defaults.bool(forKey: "demoLibrary") }
    /// `title=page;title=page`, most recently read first. The last page marks a comic finished.
    static var progress: [(title: String, page: Int)] {
        (defaults.string(forKey: "demoProgress") ?? "")
            .split(separator: ";")
            .compactMap { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2, let page = Int(parts[1]) else { return nil }
                return (parts[0], page)
            }
    }
    static var openTitle: String? { defaults.string(forKey: "demoOpen") }
    static var infoTitle: String? { defaults.string(forKey: "demoInfo") }
    static var page: Int? { defaults.object(forKey: "demoPage") == nil ? nil : defaults.integer(forKey: "demoPage") }
    /// "visible" keeps the reader controls on screen; "hidden" starts without them.
    static var chrome: String? { defaults.string(forKey: "demoChrome") }
    /// Reading mode for the opened comic: "paged" or "vertical".
    static var mode: ReadingMode? { defaults.string(forKey: "demoMode").flatMap { ReadingMode(rawValue: $0) } }
    /// Opens a reader sheet: "pages" or "settings".
    static var sheet: String? { defaults.string(forKey: "demoSheet") }
    /// Creates two sample collections if there are none.
    static var createsCollections: Bool { defaults.bool(forKey: "demoCollections") }
    /// Opens the named collection (or `-demoSeries` series) from the library.
    static var collectionName: String? { defaults.string(forKey: "demoCollection") }
    static var seriesName: String? { defaults.string(forKey: "demoSeries") }
    /// Starts the library in selection mode with these comics (by title, comma-separated) selected.
    static var selectedTitles: [String] {
        (defaults.string(forKey: "demoSelect") ?? "").split(separator: ",").map(String.init)
    }
    /// Selects a tab: "readingNow", "library", "search" or "settings".
    static var tab: AppTab? { defaults.string(forKey: "demoTab").flatMap { AppTab(rawValue: $0) } }
    /// Opens a comics grid in the Library tab: "all", "device" or a linked folder's name.
    static var libraryScope: String? { defaults.string(forKey: "demoScope") }
    /// Starts the Search tab with this text.
    static var searchText: String? { defaults.string(forKey: "demoSearch") }
    /// Opens a settings page: "readers", "gestures", "filters" or "presets".
    static var settingsPage: String? { defaults.string(forKey: "demoSettings") }
    /// Opens Library ▸ Web Server, which starts the upload server.
    static var opensWebServer: Bool { defaults.bool(forKey: "demoWebServer") }
    /// Whether the launch shows something inside the Library tab.
    static var browsesLibrary: Bool {
        collectionName != nil || seriesName != nil || libraryScope != nil || !selectedTitles.isEmpty || opensWebServer
    }
    /// Links this folder inside Documents as a library folder (standing in for iCloud Drive).
    static var linkedFolderName: String? { defaults.string(forKey: "demoLinkFolder") }
    /// Shows the reader's page scrubbing preview.
    static var scrubs: Bool { defaults.bool(forKey: "demoScrub") }
    /// Starts on the end-of-comic card.
    static var showsEnd: Bool { defaults.bool(forKey: "demoEnd") }
}
#endif
