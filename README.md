# PhilReader

A native iOS manga/comic reader for **CBZ** files, built with SwiftUI.

## Features

- Library grid with cover thumbnails and reading-progress badges
- Import `.cbz` / `.zip`, `.cbr` / `.rar`, `.cb7` / `.7z`, `.pdf` and comic `.epub`
  files or folders of images via the in-app picker or "Open in…" from the Files app
- Guided view: read panel by panel, with panels detected on the device
- Full-screen paged reader with pinch and double-tap zoom
- Pages load lazily: only the pages around the one you're reading are decoded,
  downsampled to screen size, so long volumes stay light on memory
- Right-to-left (manga) reading by default, switchable in reader settings
- Tap the page edges to turn pages, tap the middle to show or hide controls
- Direction-aware page scrubber and remembered reading position
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

## Trying it out

- **Screenshots from CI:** every CI run launches the app in an iPhone simulator
  with a generated sample manga and uploads screenshots (and the sample
  `.cbz`) as the `screenshots` artifact on the run's page under *Actions*.
- **Simulator on a Mac:** open the project in Xcode, run it, and drag a
  `.cbz` onto the simulator. To make a sample comic:
  `swift Scripts/make-sample-cbz.swift "Sample Manga.cbz"`.
- **Your own iPhone:** plug it into a Mac running Xcode, pick it as the run
  destination and sign in with your Apple ID under *Signing & Capabilities*.
  A free Apple ID works; the app then needs re-installing every 7 days.
- **TestFlight:** installing without a Mac needs a paid Apple Developer
  account ($99/year) so CI can sign and upload builds.

## Project layout

| File | Purpose |
| --- | --- |
| `PhilReaderApp.swift` | App entry point; handles files opened from other apps |
| `ComicBook.swift` | Library model (title, page count, progress) |
| `CBZService.swift` | Page ordering, cover and page count for the library |
| `CBZDocument.swift` | Open archive that reads and downsamples single pages on demand |
| `ReaderModel.swift` | Lazy page loading, prefetching and a memory-bounded cache |
| `LibraryManager.swift` | Imports, persists and deletes comics; caches covers |
| `LibraryView.swift` | Library grid and import UI |
| `ReaderView.swift` | Reader screen, controls and reader settings |
| `ZoomablePage.swift` | Pinch/double-tap zoomable page with edge-tap detection |
| `DemoLaunch.swift` | Debug-only launch arguments used for CI screenshots |

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

## Third-party code

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT) for CBZ
- [SWCompression](https://github.com/tsolomko/SWCompression) (MIT) for CB7
- [Unrar.swift](https://github.com/mtgto/Unrar.swift) (MIT) for CBR, which bundles the
  UnRAR source code under its own license: *"UnRAR source code may be used in any
  software to handle RAR archives without limitations free of charge, but cannot be
  used to develop RAR (WinRAR) compatible archiver and to re-create RAR compression
  algorithm, which is proprietary."*
