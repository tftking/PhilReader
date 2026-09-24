import SwiftUI
import UIKit
import VisionKit

/// A page image that supports pinch and double-tap zoom. Single taps are
/// reported with their horizontal position (0 = left edge, 1 = right edge).
struct ZoomablePage: UIViewRepresentable {
    let image: UIImage
    var fit: PageFit = .screen
    /// Guided view: the panel to zoom to, normalised to the image (origin top-left).
    var focusRect: CGRect? = nil
    /// Lets people long-press to select, copy and translate text on the page.
    var liveText = false
    var onTap: (CGFloat) -> Void = { _ in }

    func makeUIView(context: Context) -> ZoomingPageView {
        ZoomingPageView()
    }

    func updateUIView(_ view: ZoomingPageView, context: Context) {
        view.image = image
        view.fit = fit
        view.focusRect = focusRect
        view.liveTextEnabled = liveText
        view.onTap = onTap
    }
}

final class ZoomingPageView: UIScrollView, UIScrollViewDelegate {
    var onTap: (CGFloat) -> Void = { _ in }

    var image: UIImage? {
        didSet {
            guard image !== oldValue else { return }
            imageView.image = image
            analyzeForLiveText()
            setZoomScale(minimumZoomScale, animated: false)
            lastLayoutSize = .zero
            setNeedsLayout()
        }
    }

    var fit: PageFit = .screen {
        didSet {
            guard fit != oldValue else { return }
            setZoomScale(minimumZoomScale, animated: false)
            lastLayoutSize = .zero
            setNeedsLayout()
        }
    }

    var focusRect: CGRect? {
        didSet {
            guard focusRect != oldValue else { return }
            applyFocus(animated: true)
        }
    }

    var liveTextEnabled = false {
        didSet {
            guard liveTextEnabled != oldValue else { return }
            analyzeForLiveText()
        }
    }

    private let imageView = UIImageView()
    /// Guided view: darkens everything outside the current panel.
    private let focusDim: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillRule = .evenOdd
        layer.fillColor = UIColor.black.withAlphaComponent(0.6).cgColor
        layer.opacity = 0
        return layer
    }()
    private var lastLayoutSize: CGSize = .zero

    private static let analyzer: ImageAnalyzer? = ImageAnalyzer.isSupported ? ImageAnalyzer() : nil
    private lazy var analysisInteraction: ImageAnalysisInteraction = {
        let interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = .textSelection
        interaction.isSupplementaryInterfaceHidden = true
        return interaction
    }()
    private var analysisTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        minimumZoomScale = 1
        maximumZoomScale = 8
        bouncesZoom = true
        decelerationRate = .fast
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never

        imageView.contentMode = .scaleAspectFit
        imageView.layer.addSublayer(focusDim)
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
        // Start at the top-left when the page overflows the screen (fit width / height).
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        applyFocus(animated: false)
    }

    /// Zooms to the guided-view panel, or back out to the whole page.
    private func applyFocus(animated: Bool) {
        let size = imageView.bounds.size
        guard bounds.width > 0, size.width > 0, size.height > 0 else { return }
        focusDim.frame = imageView.bounds
        guard let focus = focusRect, focus != CGRect(x: 0, y: 0, width: 1, height: 1) else {
            focusDim.opacity = 0
            if zoomScale != minimumZoomScale { setZoomScale(minimumZoomScale, animated: animated) }
            return
        }
        let panel = CGRect(x: focus.minX * size.width, y: focus.minY * size.height,
                           width: focus.width * size.width, height: focus.height * size.height)
        // Dim the rest of the page so the current panel stands out even when it is
        // already nearly full width (and so barely zooms).
        let mask = UIBezierPath(rect: imageView.bounds)
        mask.append(UIBezierPath(roundedRect: panel.insetBy(dx: -size.width * 0.006, dy: -size.width * 0.006),
                                 cornerRadius: size.width * 0.01))
        focusDim.path = mask.cgPath
        focusDim.opacity = 1
        // A little breathing room around the panel.
        zoom(to: panel.insetBy(dx: -size.width * 0.015, dy: -size.height * 0.015), animated: animated)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    /// Runs text recognition on the current page when Live Text is on.
    private func analyzeForLiveText() {
        analysisTask?.cancel()
        guard let analyzer = Self.analyzer else { return }
        guard liveTextEnabled, let image else {
            analysisInteraction.analysis = nil
            if analysisInteraction.view != nil { imageView.removeInteraction(analysisInteraction) }
            return
        }
        if analysisInteraction.view == nil {
            imageView.isUserInteractionEnabled = true
            imageView.addInteraction(analysisInteraction)
        }
        analysisInteraction.analysis = nil
        analysisTask = Task { [weak self] in
            let configuration = ImageAnalyzer.Configuration([.text])
            let analysis = try? await analyzer.analyze(image, configuration: configuration)
            guard !Task.isCancelled, let self else { return }
            self.analysisInteraction.analysis = analysis
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    private func fittedImageSize() -> CGSize {
        guard let size = image?.size, size.width > 0, size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds.size }
        let scale: CGFloat
        switch fit {
        case .screen: scale = min(bounds.width / size.width, bounds.height / size.height)
        case .width: scale = bounds.width / size.width
        case .height: scale = bounds.height / size.height
        }
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
