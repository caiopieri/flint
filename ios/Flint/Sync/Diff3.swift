// Diff3 — line-based 3-way merge (pure; no disk, no iCloud → unit-testable).
//
// Given a common ancestor (`base`) and two divergent versions (`mine`, `theirs`),
// produce a merged text plus whether any region truly conflicted. The provider
// uses `base` from the disposable SyncBaseCache; when no base exists it falls back
// to a 2-way comparison upstream (see iCloudDriveProvider).
//
// Algorithm: anchor on lines unchanged in BOTH sides (the common subsequence
// shared by base↔mine and base↔theirs). Between anchors, a region is taken from
// whichever side changed; if both changed differently it is a conflict. In a
// conflict region we keep `mine` in place — the caller preserves `theirs` in a
// `.conflict` sibling, so nothing is lost.
import Foundation

enum Diff3 {
    struct Result: Equatable {
        let text: String
        /// True if at least one region changed on both sides incompatibly.
        let hadConflict: Bool
    }

    static func merge(base: String, mine: String, theirs: String) -> Result {
        let o = lines(base)
        let a = lines(mine)
        let b = lines(theirs)

        // Whole-file fast paths (also cover the "only one side changed" case the
        // spec calls a trivial merge).
        if a == b { return Result(text: mine, hadConflict: false) }   // identical edits
        if o == a { return Result(text: theirs, hadConflict: false) } // mine unchanged → take theirs
        if o == b { return Result(text: mine, hadConflict: false) }   // theirs unchanged → take mine

        // Lines unchanged in both sides → stable anchors that segment all three.
        let inA = matchMap(o, a)   // base-index → mine-index for LCS-matched lines
        let inB = matchMap(o, b)   // base-index → theirs-index
        var anchors: [(o: Int, a: Int, b: Int)] = []
        for i in 0..<o.count {
            if let ai = inA[i], let bi = inB[i] { anchors.append((i, ai, bi)) }
        }

        var merged: [String] = []
        var conflict = false

        func emitRegion(from: (o: Int, a: Int, b: Int), to: (o: Int, a: Int, b: Int)) {
            let oSeg = Array(o[(from.o + 1)..<to.o])
            let aSeg = Array(a[(from.a + 1)..<to.a])
            let bSeg = Array(b[(from.b + 1)..<to.b])
            if aSeg == oSeg && bSeg == oSeg { merged += oSeg }       // neither changed
            else if aSeg == oSeg { merged += bSeg }                  // only theirs changed
            else if bSeg == oSeg { merged += aSeg }                  // only mine changed
            else if aSeg == bSeg { merged += aSeg }                  // both changed identically
            else { conflict = true; merged += aSeg }                 // true conflict → keep mine
        }

        var prev = (o: -1, a: -1, b: -1)
        for anchor in anchors {
            emitRegion(from: prev, to: anchor)
            merged.append(o[anchor.o])   // the stable anchor line (== a == b)
            prev = anchor
        }
        emitRegion(from: prev, to: (o: o.count, a: a.count, b: b.count))   // tail

        return Result(text: join(merged), hadConflict: conflict)
    }

    // MARK: - Line model

    /// Split into lines, losslessly: N components ↔ N-1 separators, so
    /// `join(lines(s)) == s` for any string.
    private static func lines(_ s: String) -> [String] {
        s.components(separatedBy: "\n")
    }

    private static func join(_ ls: [String]) -> String {
        ls.joined(separator: "\n")
    }

    /// Longest-common-subsequence alignment of two line arrays, returned as a map
    /// from each matched index in `x` to its partner index in `y` (both strictly
    /// increasing). Standard DP — fine for note-sized files.
    private static func matchMap(_ x: [String], _ y: [String]) -> [Int: Int] {
        let n = x.count, m = y.count
        if n == 0 || m == 0 { return [:] }
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = x[i] == y[j]
                    ? dp[i + 1][j + 1] + 1
                    : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var map: [Int: Int] = [:]
        var i = 0, j = 0
        while i < n && j < m {
            if x[i] == y[j] {
                map[i] = j; i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return map
    }
}
