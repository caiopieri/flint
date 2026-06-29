import XCTest
@testable import Flint

final class InkDocumentTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkDocumentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRoundTripForEveryPaper() throws {
        let bytes = Data([0x01, 0x02, 0x03, 0x04])

        for paper in InkDocument.Paper.allCases {
            let doc = InkDocument(paper: paper, drawingData: bytes)
            XCTAssertEqual(try InkDocument.decode(doc.encoded()), doc)
        }
    }

    func testDecodeEmptyDataReturnsDefaultDocument() throws {
        let doc = try InkDocument.decode(Data())

        XCTAssertEqual(doc.paper, .dotted)
        XCTAssertTrue(doc.drawingData.isEmpty)
    }

    func testPaperAndBytesSurviveRoundTrip() throws {
        let doc = InkDocument(paper: .grid, drawingData: Data([0x10, 0x20, 0x30]))
        let decoded = try InkDocument.decode(doc.encoded())

        XCTAssertEqual(decoded.paper, .grid)
        XCTAssertEqual(decoded.drawingData, Data([0x10, 0x20, 0x30]))
    }

    func testDataRoundTripViaFileSystemAndProviderCreateInk() async throws {
        let file = tempDir.appendingPathComponent("Sketch.ink")
        let bytes = Data([0x7A, 0x7B, 0x7C])

        try VaultFileSystem.writeData(bytes, to: file)
        XCTAssertEqual(try VaultFileSystem.readData(at: file), bytes)

        let provider = iCloudDriveProvider(root: tempDir)
        let providerFile = tempDir.appendingPathComponent("Provider.ink")
        let providerBytes = Data([0x01, 0x02, 0x03])
        try await provider.writeData(providerBytes, to: providerFile)
        let readProviderBytes = try await provider.readData(providerFile)
        XCTAssertEqual(readProviderBytes, providerBytes)

        let created = try await provider.createInk(in: tempDir, baseName: "Drawing")
        XCTAssertEqual(created.pathExtension, "ink")
        let createdBytes = try await provider.readData(created)
        XCTAssertEqual(try InkDocument.decode(createdBytes), InkDocument())
    }
}
