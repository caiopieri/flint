// Diff3Tests — the "simulated two-device offline edit" the T2 DoD asks for.
//
// Each test is one offline-conflict scenario: a common ancestor `base`, then two
// divergent versions `mine`/`theirs`. We assert the merge result and whether it
// flagged a conflict (which is what makes the provider preserve a `.conflict`
// sibling). Pure logic — no disk, no iCloud — so it's deterministic.
import XCTest
@testable import Flint

final class Diff3Tests: XCTestCase {
    private let base = "a\nb\nc\nd\ne"

    func testNonOverlappingEditsMergeCleanly() {
        // Device A edits line b; device B edits line d. Disjoint → both land.
        let r = Diff3.merge(base: base, mine: "a\nB\nc\nd\ne", theirs: "a\nb\nc\nD\ne")
        XCTAssertEqual(r.text, "a\nB\nc\nD\ne")
        XCTAssertFalse(r.hadConflict)
    }

    func testOnlyMineChanged() {
        let r = Diff3.merge(base: base, mine: "a\nB\nc\nd\ne", theirs: base)
        XCTAssertEqual(r.text, "a\nB\nc\nd\ne")
        XCTAssertFalse(r.hadConflict)
    }

    func testOnlyTheirsChanged() {
        let r = Diff3.merge(base: base, mine: base, theirs: "a\nb\nc\nD\ne")
        XCTAssertEqual(r.text, "a\nb\nc\nD\ne")
        XCTAssertFalse(r.hadConflict)
    }

    func testIdenticalEditsOnBothSides() {
        let r = Diff3.merge(base: base, mine: "a\nX\nc\nd\ne", theirs: "a\nX\nc\nd\ne")
        XCTAssertEqual(r.text, "a\nX\nc\nd\ne")
        XCTAssertFalse(r.hadConflict)
    }

    func testTrueConflictKeepsMineAndFlags() {
        // Both edit the same line differently → conflict. We keep mine in place;
        // the provider preserves theirs in a `.conflict` sibling.
        let r = Diff3.merge(base: base, mine: "a\nB1\nc\nd\ne", theirs: "a\nB2\nc\nd\ne")
        XCTAssertEqual(r.text, "a\nB1\nc\nd\ne")
        XCTAssertTrue(r.hadConflict)
    }

    func testInsertionsAtDifferentSpots() {
        let r = Diff3.merge(base: "a\nb\nc", mine: "a\nNEW\nb\nc", theirs: "a\nb\nc\nTAIL")
        XCTAssertEqual(r.text, "a\nNEW\nb\nc\nTAIL")
        XCTAssertFalse(r.hadConflict)
    }

    func testTheirsDeletesLineMineUntouched() {
        let r = Diff3.merge(base: base, mine: base, theirs: "a\nb\nd\ne")
        XCTAssertEqual(r.text, "a\nb\nd\ne")
        XCTAssertFalse(r.hadConflict)
    }

    func testNoChangeOnEitherSide() {
        let r = Diff3.merge(base: base, mine: base, theirs: base)
        XCTAssertEqual(r.text, base)
        XCTAssertFalse(r.hadConflict)
    }
}
