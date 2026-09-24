import UIKit

/// Loads reader pages lazily: the archive stays open, pages are decoded when
/// they are about to be shown, and a size-bounded cache keeps neighbours warm.
@MainActor
final class ReaderModel: ObservableObject {
    enum Phase: Equatable {
        case opening
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .opening
    @Published private(set) var pageCount = 0

    /// Longest side pages are decoded at in paged mode. Large enough to stay
    /// sharp when zoomed on any iPhone or iPad, small enough to cap oversized scans.
    static let maxPixelSize: CGFloat = 3000
    /// Width pages are decoded at in vertical mode, whatever their height.
    static let verticalMaxWidth: CGFloat = 1600
    static let thumbnailPixelSize: CGFloat = 360

    /// Decode pages sized for continuous vertical scrolling instead of paging.
    var sizesForVerticalScroll = false {
        didSet {
            guard sizesForVerticalScroll != oldValue else { return }
            cache.removeAllObjects()
            inFlight.values.forEach { $0.cancel() }
            inFlight.removeAll()
        }
    }

    private let fileURL: URL
    private var document: CBZDocument?
    private let cache = NSCache<NSNumber, UIImage>()
    private let thumbnails = NSCache<NSNumber, UIImage>()
    private var inFlight: [Int: Task<UIImage?, Never>] = [:]
    /// Width / height of pages decoded so far, so layouts don't jump on reload.
    private var aspectRatios: [Int: CGFloat] = [:]

    init(fileURL: URL) {
        self.fileURL = fileURL
        cache.totalCostLimit = 160 * 1024 * 1024
        thumbnails.totalCostLimit = 40 * 1024 * 1024
    }

    func open() async {
        guard document == nil else { return }
        let url = fileURL
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try CBZDocument(url: url)
            }.value
            self.document = document
            pageCount = document.pageCount
            phase = document.pageCount == 0 ? .failed("This archive doesn't contain any images.") : .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func cachedImage(at index: Int) -> UIImage? {
        cache.object(forKey: index as NSNumber)
    }

    func aspectRatio(at index: Int) -> CGFloat? {
        aspectRatios[index]
    }

    /// Pages already known to be landscape (usually pre-joined double-page spreads).
    func isWidePage(_ index: Int) -> Bool {
        (aspectRatios[index] ?? 0) > 1
    }

    func image(at index: Int) async -> UIImage? {
        if let image = cachedImage(at: index) { return image }
        if let task = inFlight[index] { return await task.value }
        guard let document else { return nil }

        let vertical = sizesForVerticalScroll
        let task = Task {
            await document.image(at: index, maxPixelSize: Self.maxPixelSize,
                                 maxWidth: vertical ? Self.verticalMaxWidth : nil)
        }
        inFlight[index] = task
        let image = await task.value
        if inFlight[index] == task { inFlight[index] = nil }
        guard let image, vertical == sizesForVerticalScroll else { return image }
        if image.size.height > 0 { aspectRatios[index] = image.size.width / image.size.height }
        cache.setObject(image, forKey: index as NSNumber, cost: image.memoryCost)
        return image
    }

    func thumbnail(at index: Int) async -> UIImage? {
        if let image = thumbnails.object(forKey: index as NSNumber) { return image }
        guard let document else { return nil }
        let image = await document.image(at: index, maxPixelSize: Self.thumbnailPixelSize)
        if let image { thumbnails.setObject(image, forKey: index as NSNumber, cost: image.memoryCost) }
        return image
    }

    /// Warms the cache for the pages the reader is most likely to show next.
    func prefetch(around index: Int) {
        for neighbour in [index + 1, index - 1, index + 2] {
            guard (0..<pageCount).contains(neighbour),
                  cachedImage(at: neighbour) == nil,
                  inFlight[neighbour] == nil else { continue }
            Task { _ = await image(at: neighbour) }
        }
    }
}
