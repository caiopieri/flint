import XCTest
@testable import Flint

final class InkNotebookTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkNotebookTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRoundTripForSingleAndMultiplePages() throws {
        let single = InkNotebook(pages: [
            InkNotebook.Page(paper: .dotted, drawingData: Data([0x01, 0x02]))
        ])
        XCTAssertEqual(try InkNotebook.decode(single.encoded()), single)

        let multiple = InkNotebook(pages: [
            InkNotebook.Page(paper: .blank, drawingData: Data([0x10])),
            InkNotebook.Page(paper: .lined, drawingData: Data([0x20, 0x21])),
            InkNotebook.Page(paper: .grid, drawingData: Data([0x30, 0x31, 0x32]))
        ])
        XCTAssertEqual(try InkNotebook.decode(multiple.encoded()), multiple)
    }

    func testDecodeEmptyDataReturnsDefaultNotebook() throws {
        let notebook = try InkNotebook.decode(Data())

        XCTAssertEqual(notebook.pages.count, 1)
        XCTAssertEqual(notebook.pages[0].paper, .dotted)
        XCTAssertTrue(notebook.pages[0].drawingData.isEmpty)
    }

    func testPagesPreserveOrderIDPaperAndDrawingData() throws {
        let firstID = UUID()
        let secondID = UUID()
        let notebook = InkNotebook(pages: [
            InkNotebook.Page(id: firstID, paper: .grid, drawingData: Data([0x01])),
            InkNotebook.Page(id: secondID, paper: .blank, drawingData: Data([0x02, 0x03]))
        ])

        let decoded = try InkNotebook.decode(notebook.encoded())

        XCTAssertEqual(decoded.pages.map(\.id), [firstID, secondID])
        XCTAssertEqual(decoded.pages.map(\.paper), [.grid, .blank])
        XCTAssertEqual(decoded.pages.map(\.drawingData), [Data([0x01]), Data([0x02, 0x03])])
    }

    func testDataRoundTripViaFileSystemAndProviderCreateInk() async throws {
        let file = tempDir.appendingPathComponent("Notebook.ink")
        let bytes = Data([0x7A, 0x7B, 0x7C])

        try VaultFileSystem.writeData(bytes, to: file)
        XCTAssertEqual(try VaultFileSystem.readData(at: file), bytes)

        let provider = iCloudDriveProvider(root: tempDir)
        let providerFile = tempDir.appendingPathComponent("Provider.ink")
        let providerBytes = Data([0x01, 0x02, 0x03])
        try await provider.writeData(providerBytes, to: providerFile)
        let readProviderBytes = try await provider.readData(providerFile)
        XCTAssertEqual(readProviderBytes, providerBytes)

        let created = try await provider.createInk(in: tempDir, baseName: "Notebook")
        XCTAssertEqual(created.pathExtension, "ink")
        let createdNotebook = try InkNotebook.decode(try await provider.readData(created))
        XCTAssertEqual(createdNotebook.pages.count, 1)
        XCTAssertEqual(createdNotebook.pages[0].paper, .dotted)
        XCTAssertTrue(createdNotebook.pages[0].drawingData.isEmpty)
    }

    func testRenameNotebookPreservesInkExtension() throws {
        let file = try VaultFileSystem.createInk(in: tempDir, baseName: "Notebook")

        let renamed = try VaultFileSystem.rename(file, to: "Project Notes")

        XCTAssertEqual(renamed.lastPathComponent, "Project Notes.ink")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Project Notes.md").path))
        _ = try InkNotebook.decode(try VaultFileSystem.readData(at: renamed))
    }

    func testProviderRenameNotebookPreservesInkExtension() async throws {
        let provider = iCloudDriveProvider(root: tempDir)
        let file = try await provider.createInk(in: tempDir, baseName: "Notebook")

        let renamed = try await provider.rename(file, to: "Project Notes")

        XCTAssertEqual(renamed.lastPathComponent, "Project Notes.ink")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Project Notes.md").path))
        _ = try InkNotebook.decode(try await provider.readData(renamed))
    }
}
