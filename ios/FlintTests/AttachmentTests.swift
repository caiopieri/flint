import XCTest
@testable import Flint

final class AttachmentTests: XCTestCase {
    func testImportUsesUniqueNamesAndRejectsNoteFormats() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlintAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)

        let first = try VaultFileSystem.importAttachment(from: source, into: root)
        let second = try VaultFileSystem.importAttachment(from: source, into: root)
        XCTAssertEqual(first.lastPathComponent, "photo.png")
        XCTAssertEqual(second.lastPathComponent, "photo 1.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))

        let markdown = root.appendingPathComponent("note.md")
        try Data("# Note".utf8).write(to: markdown)
        XCTAssertThrowsError(try VaultFileSystem.importAttachment(from: markdown, into: root))
    }
}
