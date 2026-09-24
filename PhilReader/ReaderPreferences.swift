import SwiftUI

// MARK: - Gestures and zoom

/// What tapping one side of the page does.
enum EdgeTapAction: String, CaseIterable, Identifiable {
    /// Turns toward that side: back on the left for comics, forward on the left for manga.
    case turnTowardSide
    case nextPage
    case previousPage
    case toggleControls
    case nothing

    var id: Self { self }

    var label: String {
        switch self {
        case .turnTowardSide: return "Turn Page Toward Side"
        case .nextPage: return "Next Page"
        case .previousPage: return "Previous Page"
        case .toggleControls: return "Show or Hide Controls"
        case .nothing: return "Nothing"
        }
    }
}

/// How much of each side of the screen counts as a page-turn tap.
enum TapZoneSize: String, CaseIterable, Identifiable {
    case narrow, medium, wide

    var id: Self { self }
    var label: String { rawValue.capitalized }

    /// Fraction of the screen width on each side.
    var fraction: CGFloat {
        switch self {
        case .narrow: return 0.2
        case .medium: return 0.3
        case .wide: return 0.4
        }
    }
}

/// Zoom level for a double tap.
enum DoubleTapZoom: String, CaseIterable, Identifiable {
    case off, small, medium, large

    var id: Self { self }

    var label: String {
        switch self {
        case .off: return "Off"
        case .small: return "2×"
        case .medium: return "2.5×"
        case .large: return "4×"
        }
    }

    var scale: CGFloat? {
        switch self {
        case .off: return nil
        case .small: return 2
        case .medium: return 2.5
        case .large: return 4
        }
    }
}

/// Resolves where a tap at `x` (0 = left edge, 1 = right edge) should go.
enum TapZones {
    enum Outcome: Equatable {
        case forward, backward, toggleControls, nothing
    }

    static func outcome(atFraction x: CGFloat, zone: CGFloat, left: EdgeTapAction, right: EdgeTapAction,
                        rightToLeft: Bool) -> Outcome {
        let action: EdgeTapAction
        let isLeft: Bool
        if x < zone {
            action = left
            isLeft = true
        } else if x > 1 - zone {
            action = right
            isLeft = false
        } else {
            return .toggleControls
        }
        switch action {
        case .turnTowardSide:
            // The left side goes back in left-to-right reading and forward in manga.
            return isLeft == rightToLeft ? .forward : .backward
        case .nextPage: return .forward
        case .previousPage: return .backward
        case .toggleControls: return .toggleControls
        case .nothing: return .nothing
        }
    }
}

// MARK: - Image filters

enum ImageTone: String, CaseIterable, Identifiable, Codable {
    case original, grayscale, sepia, night

    var id: Self { self }

    var label: String {
        switch self {
        case .original: return "Original"
        case .grayscale: return "Grayscale"
        case .sepia: return "Sepia"
        case .night: return "Night"
        }
    }
}

/// Brightness, contrast and tone adjustments for pages, applied while reading.
struct ImageFilterSettings: Equatable, Codable {
    var brightness: Double = 0
    var contrast: Double = 1
    var tone: ImageTone = .original

    static let brightnessRange: ClosedRange<Double> = -0.3...0.3
    static let contrastRange: ClosedRange<Double> = 0.6...1.6

    var isOriginal: Bool { self == ImageFilterSettings() }
}

extension View {
    /// Applies the reader's image filters to pages.
    @ViewBuilder
    func pageFilters(_ filters: ImageFilterSettings?) -> some View {
        if let filters, !filters.isOriginal {
            self
                .brightness(filters.brightness)
                .contrast(filters.contrast)
                .grayscale(filters.tone == .grayscale || filters.tone == .sepia ? 1 : 0)
                .colorMultiply(filters.tone == .sepia ? Color(red: 1, green: 0.89, blue: 0.72) : .white)
                .modifier(InvertIf(active: filters.tone == .night))
        } else {
            self
        }
    }
}

private struct InvertIf: ViewModifier {
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            // Inverted pages read as white line art on black, softened a little.
            content.colorInvert().grayscale(1).opacity(0.88)
        } else {
            content
        }
    }
}

// MARK: - Presets

/// A saved set of reader settings that can be applied in one go.
struct ReaderPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var mode: ReadingMode
    var rightToLeft: Bool
    var fit: String
    var transition: String
    var guided: Bool
    var spreads: Bool
    var background: String
    var filters: ImageFilterSettings

    /// Presets that are always available.
    static let builtIn: [ReaderPreset] = [
        ReaderPreset(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!, name: "Manga",
                     mode: .paged, rightToLeft: true, fit: PageFit.screen.rawValue,
                     transition: PageTransition.slide.rawValue, guided: false, spreads: true,
                     background: ReaderBackground.black.rawValue, filters: ImageFilterSettings()),
        ReaderPreset(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!, name: "Comics",
                     mode: .paged, rightToLeft: false, fit: PageFit.screen.rawValue,
                     transition: PageTransition.slide.rawValue, guided: false, spreads: true,
                     background: ReaderBackground.black.rawValue, filters: ImageFilterSettings()),
        ReaderPreset(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!, name: "Webtoon",
                     mode: .vertical, rightToLeft: false, fit: PageFit.width.rawValue,
                     transition: PageTransition.slide.rawValue, guided: false, spreads: false,
                     background: ReaderBackground.black.rawValue, filters: ImageFilterSettings()),
        ReaderPreset(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A004")!, name: "Guided",
                     mode: .paged, rightToLeft: false, fit: PageFit.screen.rawValue,
                     transition: PageTransition.slide.rawValue, guided: true, spreads: false,
                     background: ReaderBackground.black.rawValue, filters: ImageFilterSettings()),
    ]

    var isBuiltIn: Bool { Self.builtIn.contains { $0.id == id } }

    var summary: String {
        var parts = [mode == .vertical ? "Continuous" : (rightToLeft ? "Right to left" : "Left to right")]
        if guided { parts.append("Guided View") }
        if mode == .paged, let fit = PageFit(rawValue: fit), fit != .screen { parts.append("Fit \(fit.label)") }
        if !filters.isOriginal { parts.append("Filters") }
        return parts.joined(separator: " · ")
    }

    /// The reader defaults as they are now.
    static func current(named name: String, in defaults: UserDefaults = .standard) -> ReaderPreset {
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        return ReaderPreset(
            name: name,
            mode: defaults.string(forKey: ReaderKeys.mode).flatMap(ReadingMode.init(rawValue:)) ?? .paged,
            rightToLeft: bool(ReaderKeys.rightToLeft, true),
            fit: defaults.string(forKey: ReaderKeys.fit) ?? PageFit.screen.rawValue,
            transition: defaults.string(forKey: ReaderKeys.transition) ?? PageTransition.slide.rawValue,
            guided: bool(ReaderKeys.guided, false),
            spreads: bool(ReaderKeys.spreads, true),
            background: defaults.string(forKey: ReaderKeys.background) ?? ReaderBackground.black.rawValue,
            filters: StoredFilters(rawValue: defaults.string(forKey: ReaderKeys.filters) ?? "")?.value
                ?? ImageFilterSettings()
        )
    }

    /// Makes this preset the reader defaults.
    func apply(to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: ReaderKeys.mode)
        defaults.set(rightToLeft, forKey: ReaderKeys.rightToLeft)
        defaults.set(fit, forKey: ReaderKeys.fit)
        defaults.set(transition, forKey: ReaderKeys.transition)
        defaults.set(guided, forKey: ReaderKeys.guided)
        defaults.set(spreads, forKey: ReaderKeys.spreads)
        defaults.set(background, forKey: ReaderKeys.background)
        defaults.set(StoredFilters(filters).rawValue, forKey: ReaderKeys.filters)
        if !filters.isOriginal { defaults.set(true, forKey: ReaderKeys.filtersEnabled) }
    }
}

/// Custom presets, stored as JSON so `@AppStorage` can hold them.
struct PresetList: RawRepresentable, Equatable {
    var items: [ReaderPreset]

    init(_ items: [ReaderPreset] = []) { self.items = items }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let items = try? JSONDecoder().decode([ReaderPreset].self, from: data) else { return nil }
        self.items = items
    }

    var rawValue: String {
        (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

/// Image filter settings, stored as JSON so `@AppStorage` can hold them.
struct StoredFilters: RawRepresentable, Equatable {
    var value: ImageFilterSettings

    init(_ value: ImageFilterSettings = ImageFilterSettings()) { self.value = value }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let value = try? JSONDecoder().decode(ImageFilterSettings.self, from: data) else { return nil }
        self.value = value
    }

    var rawValue: String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// `UserDefaults` keys for reader settings shared by several screens.
enum ReaderKeys {
    static let mode = "reader.mode"
    static let rightToLeft = "reader.rightToLeft"
    static let fit = "reader.fit"
    static let transition = "reader.transition"
    static let guided = "reader.guided"
    static let spreads = "reader.spreads"
    static let background = "reader.background"
    static let filters = "reader.filters"
    static let filtersEnabled = "reader.filtersEnabled"
    static let presets = "reader.presets"
    static let dragToClose = "reader.dragToClose"
    static let avoidMargins = "reader.avoidMargins"
    static let leftTap = "gesture.leftTap"
    static let rightTap = "gesture.rightTap"
    static let tapZone = "gesture.tapZone"
    static let doubleTapZoom = "zoom.doubleTap"
}

// MARK: - Environment

private struct PullToCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct DoubleTapScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat? = 2.5
}

private struct PageFiltersKey: EnvironmentKey {
    static let defaultValue: ImageFilterSettings? = nil
}

extension EnvironmentValues {
    /// Image filters for pages; `nil` shows them unfiltered.
    var pageFilters: ImageFilterSettings? {
        get { self[PageFiltersKey.self] }
        set { self[PageFiltersKey.self] = newValue }
    }

    /// Set when pulling a page down past its top edge should close the reader.
    var pullToClose: (() -> Void)? {
        get { self[PullToCloseKey.self] }
        set { self[PullToCloseKey.self] = newValue }
    }

    /// How far a double tap zooms in; `nil` turns double-tap zoom off.
    var doubleTapScale: CGFloat? {
        get { self[DoubleTapScaleKey.self] }
        set { self[DoubleTapScaleKey.self] = newValue }
    }
}
