import SwiftUI

@main
struct PhilReaderApp: App {
    @StateObject private var libraryManager = LibraryManager.shared
    @StateObject private var appLock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

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
