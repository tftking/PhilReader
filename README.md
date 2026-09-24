# PhilReader

A native iOS manga/comic reader for **CBZ** files, built with SwiftUI.

## Features

- Library grid with cover thumbnails and reading-progress badges
- Import `.cbz` / `.zip` files via the in-app picker or "Open in…" from the Files app
- Full-screen paged reader with pinch and double-tap zoom
- Right-to-left (manga) reading mode
- Page slider and remembered reading position
- iPhone and iPad, iOS 16+

## Requirements

- Xcode 15 or later
- iOS 16.0+ deployment target
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (resolved automatically via Swift Package Manager)

## Getting started

1. Clone the repo and open `PhilReader.xcodeproj` in Xcode.
2. Let Xcode resolve the Swift package dependencies.
3. Select your development team under *Signing & Capabilities*.
4. Build and run on a simulator or device.

To try it out in the simulator, drag a `.cbz` file onto the simulator window
or into the Files app, then import it from the library's **+** button.

## Project layout

| File | Purpose |
| --- | --- |
| `PhilReaderApp.swift` | App entry point; handles files opened from other apps |
| `ComicBook.swift` | Library model (title, page count, progress) |
| `CBZService.swift` | Reads CBZ archives: sorted image entries, cover, pages |
| `LibraryManager.swift` | Imports, persists and deletes comics; caches covers |
| `LibraryView.swift` | Library grid and import UI |
| `ReaderView.swift` | Paged reader, zoomable pages, reader settings |

## CBZ format notes

A CBZ is a ZIP archive of images. PhilReader reads `jpg`, `jpeg`, `png`,
`gif`, `webp`, `bmp` and `tiff` entries, ignores `__MACOSX` metadata, and
orders pages by natural (numeric-aware) filename sort, so `page2` comes
before `page10`.

## Roadmap ideas

- Load pages lazily instead of decoding the whole volume up front (reduces memory on long volumes)
- Remember reading direction per comic, defaulting to right-to-left for manga
- Two-page spread on iPad in landscape
- Support for `.cbr` (RAR) and `.cb7` archives
- Series grouping and sorting in the library
