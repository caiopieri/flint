import PencilKit
import UIKit

enum InkRenderer {
    /// Decodifica o desenho do documento e renderiza um PNG cabendo em `maxSize`
    /// (pontos) na `scale` dada. Desenho vazio -> PNG transparente de `maxSize`.
    static func thumbnailPNG(for doc: InkDocument, maxSize: CGSize, scale: CGFloat) throws -> Data {
        let drawing = doc.drawingData.isEmpty ? PKDrawing() : try PKDrawing(data: doc.drawingData)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: maxSize, format: format)

        return renderer.pngData { _ in
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
