import XCTest
@testable import Flint

final class ModelStoreTests: XCTestCase {
    func testRecommendedCatalogIsPinnedToHTTPSAndHasIntegrityMetadata() {
        let models = AIModelCatalog.recommended

        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertEqual(models.count, 2)
        for model in models {
            XCTAssertEqual(model.downloadURL.scheme, "https")
            XCTAssertGreaterThan(model.expectedBytes, 0)
            XCTAssertEqual(model.sha256.count, 64)
            XCTAssertFalse(model.fileName.contains("/"))
        }
    }
}
