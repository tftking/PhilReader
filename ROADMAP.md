# PhilReader roadmap

Goal: a sleek, native comic and manga reader on par with
[Panels](https://www.panels.app/). Items are grouped into phases that each
ship on their own; ✅ = done, 🚧 = in progress.

## Phase 1 — Library that feels great 🚧
- ✅ Lazy page loading with a memory-bounded cache
- 🚧 Sleek dark library design: 2:3 covers, shadows, unread dots, progress bars
- 🚧 "Continue Reading" shelf ordered by last opened
- 🚧 Search, sort (recently read / added / title) and filters (unread, in progress, finished)
- 🚧 Mark as read / unread, delete, info from a context menu
- 🚧 Comic detail sheet with cover, metadata, summary and Read / Continue button
- 🚧 `ComicInfo.xml` metadata: series, number, volume, writer, artist, publisher, year, summary, manga direction

## Phase 2 — Reader modes and controls
- Reading presets: horizontal paged, vertical paged, continuous vertical scroll (webtoon)
- Double-page spreads on iPad / landscape, with wide-page detection
- Fit modes: fit screen, fit width, fit height
- Page transitions: slide, fade, none
- Page thumbnail strip / grid for quick navigation
- Bookmarks
- Per-comic settings (direction and mode remembered per comic, auto right-to-left from metadata)
- "Next issue" prompt at the end of a comic in a series
- Reader background colour (black / dark grey / white)
- Live Text: select, copy and translate text on pages
- Keyboard shortcuts and hardware keyboard page turns

## Phase 3 — Formats
- PDF (PDFKit)
- Folders of images
- CB7 (7-Zip)
- CBR (RAR, needs a RAR decoding library, check licensing)
- Comic EPUB (fixed-layout)

## Phase 4 — Organisation
- Collections / folders with custom colours and cover images
- Automatic series grouping from metadata and filenames
- Multi-select: mark read, move to collection, delete
- Grid and list layouts; cover size slider
- Drag and drop import on iPad

## Phase 5 — Sources
- OPDS client: browse, search, stream and download
- Komga and Kavita, with reading progress synced back to the server
- iCloud Drive library folder

## Phase 6 — Sync, privacy and platforms
- iCloud progress sync across iPhone, iPad and Mac (needs a paid Apple Developer account)
- Lock with Face ID / Touch ID / passcode
- Mac app (Designed for iPad or Mac Catalyst)
- Guided view: panel-by-panel reading (panel detection with Vision)

## Out of scope for now
- Paid tier / subscriptions
- Store or DRM-protected content
