#if DEBUG
import Foundation

/// Debug-only launch arguments that put the app into a known state, used by
/// CI to capture simulator screenshots. For example:
///
///     xcrun simctl launch booted com.philreader.app \
///         -demoComic "Sample Manga.cbz" -demoOpenReader YES -demoPage 3 -demoChrome visible
///
/// `-demoComic` names a file in the app's Documents folder to import on launch.
enum DemoLaunch {
    private static var defaults: UserDefaults { .standard }

    static var comicFileName: String? { defaults.string(forKey: "demoComic") }
    static var opensReader: Bool { defaults.bool(forKey: "demoOpenReader") }
    static var page: Int? { defaults.object(forKey: "demoPage") == nil ? nil : defaults.integer(forKey: "demoPage") }
    /// "visible" keeps the reader controls on screen; "hidden" starts without them.
    static var chrome: String? { defaults.string(forKey: "demoChrome") }
}
#endif
