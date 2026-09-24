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

    /// Longest side pages are decoded at. Large enough to stay sharp when
    /// zoomed on any iPhone or iPad, small enough to cap oversized scans.
    static let maxPixelSize: CGFloat = 3000

    private let fileURL: URL
    private var document: CBZDocument?
    private let cache = NSCache<NSNumber, UIImage>()
    private var inFlight: [Int: Task<UIImage?, Never>] = [:]

    init(fileURL: URL) {
        self.fileURL = fileURL
        cache.totalCostLimit = 160 * 1024 * 1024
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

    func image(at index: Int) async -> UIImage? {
        if let image = cachedImage(at: index) { return image }
        if let task = inFlight[index] { return await task.value }
        guard let document else { return nil }

        let task = Task { await document.image(at: index, maxPixelSize: Self.maxPixelSize) }
        inFlight[index] = task
        let image = await task.value
        inFlight[index] = nil
        if let image {
            cache.setObject(image, forKey: index as NSNumber, cost: image.memoryCost)
        }
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
