import PencilKit
import UIKit
import XCTest
@testable import Flint

final class InkRendererTests: XCTestCase {
    func testEmptyDrawingProducesPNG() throws {
        let png = try InkRenderer.pagePNG(
            InkNotebook.Page(),
            maxSize: CGSize(width: 256, height: 256),
            scale: 2
        )

        XCTAssertFalse(png.isEmpty)
        XCTAssertTrue(isPNG(png))
    }

    func testStrokeDrawingProducesPNG() throws {
        let drawing = PKDrawing(strokes: [stroke()])
        let page = InkNotebook.Page(paper: .blank, drawingData: drawing.dataRepresentation())

        let png = try InkRenderer.pagePNG(
            page,
            maxSize: CGSize(width: 256, height: 256),
            scale: 2
        )

        XCTAssertFalse(png.isEmpty)
        XCTAssertTrue(isPNG(png))
    }

    private func isPNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    }

    private func stroke() -> PKStroke {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 20, y: 20),
                timeOffset: 0,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 180, y: 160),
                timeOffset: 0.1,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let ink = PKInk(.pen, color: .black)
        return PKStroke(ink: ink, path: path)
    }
}
