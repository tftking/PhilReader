import SwiftUI

@main
struct PhilReaderApp: App {
    @StateObject private var libraryManager = LibraryManager.shared
    @StateObject private var appLock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.styleNavigationTitles()
    }

    /// SF Pro Rounded for large and inline titles: softer and more modern than the default.
    private static func styleNavigationTitles() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }
        // SwiftUI's navigation bars use the appearance objects, not the legacy title attributes.
        func appearance(_ configure: (UINavigationBarAppearance) -> Void) -> UINavigationBarAppearance {
            let appearance = UINavigationBarAppearance()
            configure(appearance)
            appearance.largeTitleTextAttributes = [.font: rounded(34, .bold)]
            appearance.titleTextAttributes = [.font: rounded(17, .semibold)]
            return appearance
        }
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance { $0.configureWithDefaultBackground() }
        bar.compactAppearance = appearance { $0.configureWithDefaultBackground() }
        bar.scrollEdgeAppearance = appearance { $0.configureWithTransparentBackground() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryManager)
                .environmentObject(appLock)
                .overlay {
                    if appLock.isLocked {
                        LockScreen(isLocked: true).transition(.opacity)
                    } else if appLock.isEnabled && scenePhase != .active {
                        // Hide the library in the app switcher.
                        LockScreen(isLocked: false)
                    }
                }
                .onOpenURL { url in
                    Task { await libraryManager.importComic(from: url) }
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                appLock.lock()
            case .active:
                Task { await libraryManager.rescanLinkedFolders() }
            default:
                break
            }
        }
    }
}
