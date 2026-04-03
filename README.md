# PhilReader

A clean, fast CBZ comic reader for iOS and iPadOS — inspired by Panels.

## Features

- 📚 **Library Grid** — Cover thumbnails with reading progress badges
- 📖 **Paged Reader** — Swipe left/right through pages, full-screen
- 🔍 **Pinch & Double-tap Zoom** — Up to 5× zoom on any page
- 🔄 **Right-to-Left Mode** — Manga reading direction toggle
- 📥 **File Import** — Via the + button *or* "Open with PhilReader" from Files app
- 💾 **Progress Saving** — Resumes where you left off, auto-saves on close
- 🗑️ **Delete** — Long-press a comic to remove it
- 📱 iPad & iPhone support

## Requirements

- iOS 16.0+
- Xcode 15+

## Setup

1. Clone the repo
2. Open `PhilReader.xcodeproj` in Xcode
3. Xcode will automatically resolve the [ZipFoundation](https://github.com/weichsel/ZipFoundation) Swift Package dependency
4. Set your Team in *Signing & Capabilities*
5. Build & Run on a device or simulator

## Importing Comics

**From the app:** Tap the **+** button → browse your Files  
**From Files app:** Long-press a `.cbz` → Share → Open with PhilReader

## Architecture

| File | Purpose |
|------|---------|
| `PhilReaderApp.swift` | App entry, handles file open URLs |
| `ContentView.swift` | Root view |
| `LibraryView.swift` | Grid of comics, file import |
| `ReaderView.swift` | Full-screen paged reader + zoom |
| `ComicBook.swift` | Data model |
| `CBZService.swift` | ZIP extraction via ZipFoundation |
| `LibraryManager.swift` | Import, persist, cover cache |

## Dependencies

- [ZipFoundation](https://github.com/weichsel/ZipFoundation) — Swift ZIP library (resolved automatically by Xcode SPM)

## License

MIT
