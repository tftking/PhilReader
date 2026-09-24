# PhilReader roadmap

Goal: a sleek, native comic and manga reader on par with
[Panels](https://www.panels.app/). Items are grouped into phases that each
ship on their own; ✅ = done, 🚧 = in progress.

## Phase 1 — Library that feels great ✅
- ✅ Lazy page loading with a memory-bounded cache
- ✅ Sleek library design: 2:3 covers, shadows, unread dots, progress bars
- ✅ "Continue Reading" shelf ordered by last opened
- ✅ Search, sort (recently read / added / title) and filters (unread, in progress, finished)
- ✅ Mark as read / unread, delete, info from a context menu
- ✅ Comic detail sheet with cover, metadata, summary and Read / Continue button
- ✅ `ComicInfo.xml` metadata: series, number, volume, writer, artist, publisher, year, summary, manga direction

## Phase 2 — Reader modes and controls ✅
- ✅ Reading modes: horizontal paged and continuous vertical scroll (webtoon)
- ✅ Two-page spreads in landscape, with the cover and wide pages on their own
- ✅ Fit modes: fit screen, fit width, fit height
- ✅ Page thumbnail grid for quick navigation
- ✅ Bookmarks
- ✅ Per-comic direction and mode, auto right-to-left from metadata
- ✅ End-of-comic card with "Read Next" for the next issue in a series
- ✅ Reader background colour (black / dark grey / white)
- ✅ Live Text: select, copy and translate text on pages
- ✅ Keyboard page turns (arrows, space, shift-space, escape)
- ✅ Page turns: slide, fade or none (swipe or tap in every mode)
- ✅ Zoom in vertical scroll mode: pinch or double-tap, drag sideways while zoomed

## Phase 3 — Formats ✅
- ✅ PDF (PDFKit), rendered at the size needed so pages stay sharp; title and author as metadata
- ✅ Folders of images (including subfolders and `ComicInfo.xml`)
- ✅ More image types inside archives: HEIC, AVIF, TIFF
- ✅ CB7 (7-Zip, via SWCompression) and CBR (RAR, via Unrar.swift), unpacked once to a cache
- ✅ Comic EPUB (fixed-layout): spine order, `<img>` and SVG page wrappers, right-to-left spines, title/author

## Phase 4 — Organisation ✅
- ✅ Collections with custom colours and a chosen cover comic
- ✅ Automatic series stacks from metadata or file names, with a series page and "Continue" button
- ✅ Multi-select: mark read / unread, add to collection, delete
- ✅ Grid and list layouts; small / medium / large covers
- ✅ Drag and drop import (iPad, Mac)

## Phase 5 — Library folders ✅
- ✅ Link folders in iCloud Drive (or anywhere in Files): comics are read in place, new files
  appear automatically, iCloud files download on open, unlinking never deletes files
- Not planned: OPDS / Komga / Kavita servers

## Phase 6 — Modern design, privacy and platforms 🚧
- ✅ App icon
- ✅ Panels-style tabs: Reading Now, Library, Settings, with Search beside the tab bar (iOS 18+)
- ✅ Reading Now: current comic, Next Up, Pick Up Where You Left Off, Finished
- ✅ Settings: library folders, reading defaults, privacy, cache, acknowledgements
- ✅ Lock with Face ID / Touch ID / passcode, hidden in the app switcher
- ✅ Mac: runs on Apple Silicon Macs as a "Designed for iPad" app (drag and drop, keyboard page turns)
- iCloud progress sync across devices (needs a paid Apple Developer account)
- ✅ Guided view: panel-by-panel reading, with on-device gutter-based panel detection (right-to-left for manga)

## Phase 7 — Panels parity ✅
- ✅ Panels-style reader controls: glass buttons, title menu, scrub bar with page thumbnails
- ✅ Reading time: shown while reading and totalled per comic
- ✅ Gestures and Zoom: choose what each side tap does, tap zone width, double-tap zoom level
- ✅ Drag down to close the paginated reader
- ✅ Image filters: brightness, contrast, grayscale, sepia and night
- ✅ Presets: built-in Manga, Comics, Webtoon and Guided, plus your own
- ✅ Avoid device margins
- ✅ Web server: upload comics from a computer's browser over Wi-Fi

## Out of scope for now
- Paid tier / subscriptions
- Store or DRM-protected content
