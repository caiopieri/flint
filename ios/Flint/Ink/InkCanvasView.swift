import PencilKit
import SwiftUI

struct InkCanvasView: UIViewRepresentable {
    var drawing: PKDrawing
    var drawingRevision: Int
    var paper: InkNotebook.Paper
    var onDrawingChanged: (PKDrawing) -> Void

    func makeUIView(context: Context) -> InkCanvasContainerView {
        let view = InkCanvasContainerView()
        view.canvasView.delegate = context.coordinator
        view.canvasView.drawingPolicy = UIDevice.current.userInterfaceIdiom == .pad ? .pencilOnly : .anyInput
        return view
    }

    func updateUIView(_ view: InkCanvasContainerView, context: Context) {
        view.paper = paper
        context.coordinator.parent = self
        context.coordinator.apply(drawing, revision: drawingRevision, to: view)
        context.coordinator.installToolPickerIfNeeded(for: view.canvasView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: InkCanvasView
        private var toolPicker: PKToolPicker?
        private weak var installedWindow: UIWindow?
        private var loadedRevision: Int?
        private var isApplyingDrawing = false

        init(parent: InkCanvasView) {
            self.parent = parent
        }

        func apply(_ drawing: PKDrawing, revision: Int, to view: InkCanvasContainerView) {
            guard loadedRevision != revision else { return }
            isApplyingDrawing = true
            view.canvasView.drawing = drawing
            isApplyingDrawing = false
            loadedRevision = revision
        }

        func installToolPickerIfNeeded(for canvasView: PKCanvasView) {
            guard let window = canvasView.window else {
                DispatchQueue.main.async { [weak self, weak canvasView] in
                    guard let self, let canvasView else { return }
                    self.installToolPickerIfNeeded(for: canvasView)
                }
                return
            }
            guard installedWindow !== window else { return }
            let picker = toolPicker ?? PKToolPicker()
            toolPicker = picker
            picker.addObserver(canvasView)
            picker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
            installedWindow = window
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingDrawing else { return }
            parent.onDrawingChanged(canvasView.drawing)
        }
    }
}

final class InkCanvasContainerView: UIView, UIScrollViewDelegate {
    private enum Layout {
        static let pageSize = CGSize(width: 768, height: 1024)
        static let pagePadding: CGFloat = 24
    }

    private let scrollView = UIScrollView()
    private let pageView = UIView()
    private let paperView = InkPaperView()
    private var didConfigureInitialZoom = false
    let canvasView = PKCanvasView()
    var paper: InkNotebook.Paper = .dotted {
        didSet { paperView.paper = paper }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .secondarySystemBackground

        scrollView.delegate = self
        scrollView.backgroundColor = .secondarySystemBackground
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addSubview(scrollView)

        pageView.backgroundColor = InkPaperRenderer.backgroundColor
        pageView.clipsToBounds = true
        pageView.layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
        pageView.layer.borderColor = InkPaperRenderer.ruleColor.cgColor
        scrollView.addSubview(pageView)

        paperView.paper = paper
        pageView.addSubview(paperView)

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        canvasView.clipsToBounds = true
        pageView.addSubview(canvasView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(doubleTap)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        paperView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            paperView.leadingAnchor.constraint(equalTo: pageView.leadingAnchor),
            paperView.trailingAnchor.constraint(equalTo: pageView.trailingAnchor),
            paperView.topAnchor.constraint(equalTo: pageView.topAnchor),
            paperView.bottomAnchor.constraint(equalTo: pageView.bottomAnchor),

            canvasView.leadingAnchor.constraint(equalTo: pageView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: pageView.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: pageView.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: pageView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pageView.frame = CGRect(origin: .zero, size: Layout.pageSize)
        scrollView.contentSize = Layout.pageSize
        configureZoomIfNeeded()
        centerPage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        pageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerPage()
    }

    private func configureZoomIfNeeded() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fitWidth = (bounds.width - Layout.pagePadding * 2) / Layout.pageSize.width
        let fitHeight = (bounds.height - Layout.pagePadding * 2) / Layout.pageSize.height
        let minimumZoom = max(min(fitWidth, fitHeight), 0.25)
        if abs(scrollView.minimumZoomScale - minimumZoom) > 0.001 {
            scrollView.minimumZoomScale = minimumZoom
            scrollView.maximumZoomScale = max(minimumZoom * 4, 2.5)
            if !didConfigureInitialZoom {
                scrollView.zoomScale = minimumZoom
                didConfigureInitialZoom = true
            } else if scrollView.zoomScale < minimumZoom {
                scrollView.zoomScale = minimumZoom
            }
        }
    }

    private func centerPage() {
        let scaledWidth = Layout.pageSize.width * scrollView.zoomScale
        let scaledHeight = Layout.pageSize.height * scrollView.zoomScale
        let horizontalInset = max((bounds.width - scaledWidth) / 2, Layout.pagePadding)
        let verticalInset = max((bounds.height - scaledHeight) / 2, Layout.pagePadding)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let fitZoom = scrollView.minimumZoomScale
        let writingZoom = min(max(fitZoom * 2.2, 1.0), scrollView.maximumZoomScale)
        let targetZoom = scrollView.zoomScale > fitZoom + 0.05 ? fitZoom : writingZoom

        let location = recognizer.location(in: pageView)
        let width = bounds.width / targetZoom
        let height = bounds.height / targetZoom
        let rect = CGRect(
            x: location.x - width / 2,
            y: location.y - height / 2,
            width: width,
            height: height
        )
        scrollView.zoom(to: rect, animated: true)
    }
}

private final class InkPaperView: UIView {
    var paper: InkNotebook.Paper = .dotted {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = InkPaperRenderer.backgroundColor
        isOpaque = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        InkPaperRenderer.draw(
            paper,
            in: rect,
            context: context,
            scale: window?.screen.scale ?? traitCollection.displayScale
        )
    }
}
