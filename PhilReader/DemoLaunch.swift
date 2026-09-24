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
}
#endif
