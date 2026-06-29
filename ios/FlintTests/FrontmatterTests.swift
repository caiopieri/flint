// FrontmatterTests — T5 DoD tests for the tag parser.
// Pure unit tests: no UI, no disk I/O, no async.
import XCTest
@testable import Flint

final class FrontmatterTests: XCTestCase {

    // MARK: - Frontmatter forms

    func testFlowTags() {
        let body = "---\ntags: [work, project, swift]\n---\n"
        XCTAssertEqual(tags(body), ["project", "swift", "work"])
    }

    func testFlowTagsWithSpaces() {
        let body = "---\ntags: [ work , project/ios ]\n---\n"
        XCTAssertEqual(tags(body), ["project/ios", "work"])
    }

    func testBlockTags() {
        let body = "---\ntags:\n- work\n- project\n- swift\n---\n"
        XCTAssertEqual(tags(body), ["project", "swift", "work"])
    }

    func testBlockTagsNoDash() {
        let body = "---\ntags:\n-work\n-project\n---\n"
        XCTAssertEqual(tags(body), ["project", "work"])
    }

    func testScalarSpaceSeparated() {
        let body = "---\ntags: work project swift\n---\n"
        XCTAssertEqual(tags(body), ["project", "swift", "work"])
    }

    func testScalarCommaSeparated() {
        let body = "---\ntags: work, project, swift\n---\n"
        XCTAssertEqual(tags(body), ["project", "swift", "work"])
    }

    func testTagAlias() {
        let body = "---\ntag: solo\n---\n"
        XCTAssertEqual(tags(body), ["solo"])
    }

    // MARK: - Inline #tags

    func testInlineTag() {
        XCTAssertEqual(tags("Hello #world"), ["world"])
    }

    func testInlineTagAtStart() {
        XCTAssertEqual(tags("#start of text"), ["start"])
    }

    func testInlineTagAfterNewline() {
        XCTAssertEqual(tags("line1\n#tag"), ["tag"])
    }

    func testInlineTagWithSlash() {
        XCTAssertEqual(tags("see #project/ios notes"), ["project/ios"])
    }

    func testHeadingExcluded() {
        XCTAssertEqual(tags("# Heading\n## Sub"), [])
    }

    func testWordFragExcluded() {
        XCTAssertEqual(tags("foo#bar is not a tag"), [])
    }

    func testUrlHashExcluded() {
        XCTAssertEqual(tags("visit http://example.com#section"), [])
    }

    func testPureNumberTagExcluded() {
        XCTAssertEqual(tags("issue #123 is a number"), [])
    }

    func testInlineTagWithNumber() {
        XCTAssertEqual(tags("#swift5 is valid"), ["swift5"])
    }

    // MARK: - Frontmatter + inline dedup

    func testDeduplicateCaseInsensitive() {
        let body = "---\ntags: [Work]\n---\nSee also #work notes"
        let result = tags(body)
        XCTAssertEqual(result.count, 1)
        // First spelling (frontmatter) is preserved
        XCTAssertEqual(result.first, "Work")
    }

    func testAlphabeticOrder() {
        let body = "---\ntags: [zebra, apple, mango]\n---\n"
        XCTAssertEqual(tags(body), ["apple", "mango", "zebra"])
    }

    // MARK: - Edge cases

    func testEmptyBody() {
        XCTAssertEqual(tags(""), [])
    }

    func testNoFrontmatterNoInline() {
        XCTAssertEqual(tags("Just plain text."), [])
    }

    func testMalformedFrontmatterNoClosing() {
        // No closing --- → frontmatter not parsed, but inline still works
        let body = "---\ntags: [work]\nThis has no closing fence\n#inline"
        XCTAssertEqual(tags(body), ["inline"])
    }

    func testFrontmatterMissingValue() {
        let body = "---\ntitle: Hello\n---\n"
        XCTAssertEqual(tags(body), [])
    }

    func testFrontmatterDotDotDotClosing() {
        let body = "---\ntags: [a]\n...\n"
        XCTAssertEqual(tags(body), ["a"])
    }

    func testGiantBodyDoesNotCrash() {
        let huge = String(repeating: "a ", count: 300_000)
        XCTAssertNoThrow(Frontmatter.tags(in: huge))
    }

    func testManyTagsCapped() {
        // Build a body with 200 inline tags
        let body = (1...200).map { "#tag\($0)" }.joined(separator: " ")
        let result = Frontmatter.tags(in: body)
        XCTAssertLessThanOrEqual(result.count, 100)
    }

    // MARK: - Helpers

    private func tags(_ body: String) -> [String] {
        Frontmatter.tags(in: body)
    }
}
