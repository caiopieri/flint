import XCTest
@testable import Flint

final class BoardDocumentTests: XCTestCase {
    func testRoundTripPreservesUnknownTopLevelAndNodeFields() throws {
        let data = Data(#"{"nodes":[{"id":"n1","type":"file","x":10,"y":20,"width":320,"height":180,"file":"Notes/A.md","pluginData":{"keep":true}}],"edges":[],"appMetadata":{"version":2}}"#.utf8)

        let document = try BoardDocument.decode(data)
        XCTAssertEqual(document.nodes.first?.extras["pluginData"], .object(["keep": .bool(true)]))
        XCTAssertEqual(document.extras["appMetadata"], .object(["version": .number(2)]))

        let encoded = try document.encoded()
        let roundTrip = try BoardDocument.decode(encoded)
        XCTAssertEqual(roundTrip, document)
    }

    func testRejectsTraversalDuplicateIDsAndInvalidEdges() throws {
        XCTAssertThrowsError(try BoardDocument.decode(Data(#"{"nodes":[{"id":"n1","type":"file","x":0,"y":0,"width":1,"height":1,"file":"../secret.md"}],"edges":[]}"#.utf8)))

        let duplicate = BoardNode(id: "same", type: "file", x: 0, y: 0, width: 10, height: 10)
        XCTAssertThrowsError(try BoardDocument(nodes: [duplicate, duplicate]).encoded())

        let edge = BoardEdge(id: "e1", fromNode: "missing", toNode: "also-missing")
        XCTAssertThrowsError(try BoardDocument(edges: [edge]).encoded())
    }

    func testAddingMarkdownIsSafeAndIdempotent() throws {
        let document = try BoardDocument.empty.addingMarkdown(path: "Notes/A.md", title: "A", at: BoardPoint(x: 0, y: 0))
        let same = try document.addingMarkdown(path: "Notes/A.md", title: "A", at: BoardPoint(x: 100, y: 100))
        XCTAssertEqual(same.nodes.count, 1)
        XCTAssertThrowsError(try document.addingMarkdown(path: "/absolute.md", title: "Bad", at: BoardPoint(x: 0, y: 0)))
        XCTAssertThrowsError(try document.addingMarkdown(path: "Notes/A.txt", title: "Bad", at: BoardPoint(x: 0, y: 0)))
    }

    func testRejectsOversizedDocument() {
        let padding = String(repeating: "x", count: BoardDocument.maxBytes)
        let data = Data((#"{"nodes":[],"edges":[],"padding":""# + padding + #""}"#).utf8)
        XCTAssertThrowsError(try BoardDocument.decode(data)) { error in
            XCTAssertEqual(error as? BoardDocumentError, .tooLarge)
        }
    }
}
