import SwiftUI

@main
struct PhilReaderApp: App {
    @StateObject private var libraryManager = LibraryManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryManager)
                .onOpenURL { url in
                    Task {
                        await libraryManager.importComic(from: url)
                    }
                }
        }
    }
}
