import SwiftUI
import UIKit

/// A page image that supports pinch and double-tap zoom. Single taps are
/// reported with their horizontal position (0 = left edge, 1 = right edge).
struct ZoomablePage: UIViewRepresentable {
    let image: UIImage
    var onTap: (CGFloat) -> Void = { _ in }

    func makeUIView(context: Context) -> ZoomingPageView {
        ZoomingPageView()
    }

    func updateUIView(_ view: ZoomingPageView, context: Context) {
        view.image = image
        view.onTap = onTap
    }
}

final class ZoomingPageView: UIScrollView, UIScrollViewDelegate {
    var onTap: (CGFloat) -> Void = { _ in }

    var image: UIImage? {
        didSet {
            guard image !== oldValue else { return }
            imageView.image = image
            setZoomScale(minimumZoomScale, animated: false)
            lastLayoutSize = .zero
            setNeedsLayout()
        }
    }

    private let imageView = UIImageView()
    private var lastLayoutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        decelerationRate = .fast
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize, zoomScale == minimumZoomScale else { return }
        lastLayoutSize = bounds.size
        let fitted = fittedImageSize()
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        centerContent()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    private func fittedImageSize() -> CGSize {
        guard let size = image?.size, size.width > 0, size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds.size }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func centerContent() {
        let x = max((bounds.width - contentSize.width) / 2, 0)
        let y = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                              width: size.width, height: size.height)
            zoom(to: rect, animated: true)
        }
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard bounds.width > 0 else { return }
        let x = recognizer.location(in: self).x - contentOffset.x
        onTap(x / bounds.width)
    }
}
