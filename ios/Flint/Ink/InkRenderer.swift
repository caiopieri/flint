import PencilKit
import SwiftUI
import UIKit

enum InkRenderer {
    /// Decodifica o desenho da pagina e renderiza um PNG cabendo em `maxSize`
    /// (pontos) na `scale` dada. Desenho vazio -> PNG transparente de `maxSize`.
    static func pagePNG(_ page: InkNotebook.Page, maxSize: CGSize, scale: CGFloat) throws -> Data {
        let drawing = page.drawingData.isEmpty ? PKDrawing() : try PKDrawing(data: page.drawingData)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: maxSize, format: format)

        return renderer.pngData { rendererContext in
            InkPaperRenderer.draw(
                page.paper,
                in: CGRect(origin: .zero, size: maxSize),
                context: rendererContext.cgContext,
                scale: scale
            )

            guard !drawing.bounds.isEmpty, drawing.bounds.width > 1, drawing.bounds.height > 1 else {
                return
            }

            let sourceRect = drawing.bounds.insetBy(dx: -12, dy: -12)
            let image = drawing.image(from: sourceRect, scale: scale)
            image.draw(in: fittedRect(for: sourceRect.size, inside: CGRect(origin: .zero, size: maxSize)))
        }
    }

    private static func fittedRect(for source: CGSize, inside bounds: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return bounds }
        let factor = min(bounds.width / source.width, bounds.height / source.height)
        let size = CGSize(width: source.width * factor, height: source.height * factor)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

enum InkPaperRenderer {
    static var backgroundColor: UIColor { UIColor(FlintColor.paperBackground) }
    static var ruleColor: UIColor { UIColor(FlintColor.paperRule) }

    static func draw(_ paper: InkNotebook.Paper, in rect: CGRect, context: CGContext, scale: CGFloat) {
        backgroundColor.setFill()
        context.fill(rect)

        ruleColor.setStroke()
        ruleColor.setFill()
        context.setLineWidth(1 / max(scale, 1))

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

    private static func drawHorizontalLines(in rect: CGRect, spacing: CGFloat, context: CGContext) {
        var y = spacing
        while y < rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        context.strokePath()
    }

    private static func drawVerticalLines(in rect: CGRect, spacing: CGFloat, context: CGContext) {
        var x = spacing
        while x < rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        context.strokePath()
    }

    private static func drawDots(in rect: CGRect, spacing: CGFloat, context: CGContext) {
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
