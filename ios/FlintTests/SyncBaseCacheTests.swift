// SyncBaseCacheTests — the disposable ancestor store round-trips and degrades
// gracefully (a miss returns nil, which makes the provider fall back to 2-way).
import XCTest
@testable import Flint

final class SyncBaseCacheTests: XCTestCase {
    private func makeRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRoundTrip() {
        let root = makeRoot()
        let cache = SyncBaseCache(root: root)
        let note = root.appendingPathComponent("Note.md")

        XCTAssertNil(cache.base(for: note), "no ancestor yet → nil → provider uses 2-way")
        cache.update("hello\nworld", for: note)
        XCTAssertEqual(cache.base(for: note), "hello\nworld")
    }

    func testForgetDropsAncestor() {
        let root = makeRoot()
        let cache = SyncBaseCache(root: root)
        let note = root.appendingPathComponent("Note.md")

        cache.update("x", for: note)
        cache.forget(note)
        XCTAssertNil(cache.base(for: note))
    }

    func testDistinctNotesDoNotCollide() {
        let root = makeRoot()
        let cache = SyncBaseCache(root: root)
        let a = root.appendingPathComponent("A.md")
        let b = root.appendingPathComponent("sub/B.md")

        cache.update("aaa", for: a)
        cache.update("bbb", for: b)
        XCTAssertEqual(cache.base(for: a), "aaa")
        XCTAssertEqual(cache.base(for: b), "bbb")
    }
}
