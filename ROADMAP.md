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
- Later: fade / no-animation page transitions, zoom in vertical scroll mode

## Phase 3 — Formats 🚧
- ✅ PDF (PDFKit), rendered at the size needed so pages stay sharp; title and author as metadata
- ✅ Folders of images (including subfolders and `ComicInfo.xml`)
- ✅ More image types inside archives: HEIC, AVIF, TIFF
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
