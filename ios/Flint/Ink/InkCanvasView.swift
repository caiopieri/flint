import PencilKit
import SwiftUI

struct InkCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var paper: InkDocument.Paper
    var onDrawingChanged: () -> Void

    func makeUIView(context: Context) -> InkCanvasContainerView {
        let view = InkCanvasContainerView()
        view.canvasView.delegate = context.coordinator
        view.canvasView.drawingPolicy = .anyInput
        view.canvasView.backgroundColor = .clear
        view.canvasView.isOpaque = false
        context.coordinator.installToolPicker(for: view.canvasView)
        return view
    }

    func updateUIView(_ view: InkCanvasContainerView, context: Context) {
        view.paper = paper
        if view.canvasView.drawing != drawing {
            view.canvasView.drawing = drawing
        }
        context.coordinator.parent = self
        context.coordinator.installToolPicker(for: view.canvasView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: InkCanvasView
        private var toolPicker: PKToolPicker?

        init(parent: InkCanvasView) {
            self.parent = parent
        }

        func installToolPicker(for canvasView: PKCanvasView) {
            let picker = toolPicker ?? PKToolPicker()
            toolPicker = picker
            picker.addObserver(canvasView)
            picker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            parent.onDrawingChanged()
        }
    }
}

final class InkCanvasContainerView: UIView {
    let canvasView = PKCanvasView()
    var paper: InkDocument.Paper = .dotted {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBackground
        addSubview(canvasView)
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        UIColor.secondarySystemBackground.setFill()
        context.fill(rect)

        let stroke = UIColor.separator.withAlphaComponent(0.45)
        stroke.setStroke()
        context.setLineWidth(1 / max(window?.screen.scale ?? UIScreen.main.scale, 1))

        switch paper {
        case .blank:
            break
        case .lined:
            drawHorizontalLines(in: rect, spacing: 28, context: context)
        case .grid:
            drawHorizontalLines(in: rect, spacing: 28, context: context)
            drawVerticalLines(in: rect, spacing: 28, context: context)
        case .dotted:
            drawDots(in: rect, spacing: 24, context: context)
        }
    }

    private func drawHorizontalLines(in rect: CGRect, spacing: CGFloat, context: CGContext) {
        var y = spacing
        while y < rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        context.strokePath()
    }

    private func drawVerticalLines(in rect: CGRect, spacing: CGFloat, context: CGContext) {
        var x = spacing
        while x < rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        context.strokePath()
    }

    private func drawDots(in rect: CGRect, spacing: CGFloat, context: CGContext) {
        var y = spacing
        while y < rect.maxY {
            var x = spacing
            while x < rect.maxX {
                context.fillEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                x += spacing
            }
            y += spacing
        }
    }
}
