// SearchIndex — SQLite FTS5 full-text search over the vault (T4).
//
// DISPOSABLE: the `.sqlite` file lives in Application Support (never in the vault
// or iCloud). Deleting it and re-running syncIndex in VaultStore reconstructs the
// index from the vault files with no data loss — this is the T4 DoD test.
//
// Threading: every actor method either suspends (async GRDB path) or delegates work
// to GRDB's own serial queue so the caller is never blocked long.
import CryptoKit
import Foundation
import GRDB

/// A search result returned by `SearchIndex.query`.
struct SearchHit: Sendable {
    let relativePath: String
    let title: String
    /// Body excerpt with matched terms wrapped in `SearchIndex.snippetOpen/Close`.
    let snippet: String
}

/// FTS5 search index. One actor per open vault; created by `VaultStore.beginAccess`,
/// released by `VaultStore.stopAccess` — so switching vaults swaps the index.
actor SearchIndex {
    /// Bump this when the schema changes to trigger an automatic rebuild on open.
    private static let schemaVersion = 1
    /// Delimiters injected around matched terms in `SearchHit.snippet`.
    /// The UI (VaultNavigator) maps these to `FlintColor.accentText`.
    static let snippetOpen = "⟨"
    static let snippetClose = "⟩"

    private let queue: DatabaseQueue

    /// Opens (or creates) the FTS5 database for `vaultRoot`. If the on-disk schema
    /// version doesn't match `schemaVersion`, or the file is corrupt, the index is
    /// wiped and recreated from scratch (rebuild).
    init(vaultRoot: URL) throws {
        let url = try Self.dbURL(for: vaultRoot)
        queue = try Self.openOrRebuild(at: url)
    }

    // MARK: - Diff

    /// Compares `current` (vault snapshot: relative path + mtime) against what is
    /// already indexed. Returns files that need re-reading and files to drop.
    func diff(
        current: [(path: String, mtime: Date)]
    ) async throws -> (toRead: [String], toDelete: [String]) {
        let indexed: [String: Double] = try await queue.read { db in
            var result: [String: Double] = [:]
            let rows = try Row.fetchAll(db, sql: "SELECT path, mtime FROM notes")
            for row in rows {
                guard let path: String = row[0] else { continue }
                let epoch: Double = row[1] ?? 0
                result[path] = epoch
            }
            return result
        }
        let currentSet = Set(current.map(\.path))
        var toRead: [String] = []
        for (path, mtime) in current {
            if let indexedEpoch = indexed[path] {
                // 0.5s tolerance: iCloud may shift mtimes slightly on sync
                if abs(mtime.timeIntervalSince1970 - indexedEpoch) > 0.5 {
                    toRead.append(path)
                }
            } else {
                toRead.append(path)
            }
        }
        let toDelete = Array(Set(indexed.keys).subtracting(currentSet))
        return (toRead, toDelete)
    }

    // MARK: - Apply

    /// Writes `upserts` (insert-or-replace) and removes `deletes` from the FTS5 table.
    /// FTS5 doesn't support UPDATE, so upsert = delete-then-insert by path.
    func apply(
        upserts: [(path: String, title: String, mtime: Date, body: String)],
        deletes: [String]
    ) async throws {
        try await queue.write { db in
            for path in deletes {
                try db.execute(sql: "DELETE FROM notes WHERE path = ?", arguments: [path])
            }
            for item in upserts {
                try db.execute(sql: "DELETE FROM notes WHERE path = ?", arguments: [item.path])
                try db.execute(
                    sql: "INSERT INTO notes(path, title, body, mtime) VALUES (?, ?, ?, ?)",
                    arguments: [
                        item.path,
                        item.title,
                        item.body,
                        item.mtime.timeIntervalSince1970,
                    ]
                )
            }
        }
    }

    // MARK: - Query

    /// Returns up to 50 ranked hits for `raw`. Empty or whitespace → `[]`.
    /// Invalid FTS5 syntax is sanitized; a parse error degrades to `[]` rather
    /// than crashing.
    func query(_ raw: String) async throws -> [SearchHit] {
        let sanitized = Self.sanitize(raw)
        guard !sanitized.isEmpty else { return [] }
        do {
            return try await queue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT path, title,
                           snippet(notes, -1, ?, ?, '…', 10)
                    FROM notes
                    WHERE notes MATCH ?
                    ORDER BY bm25(notes)
                    LIMIT 50
                """, arguments: [Self.snippetOpen, Self.snippetClose, sanitized])
                return rows.compactMap { row -> SearchHit? in
                    guard let path: String = row[0],
                          let title: String = row[1],
                          let snip: String = row[2] else { return nil }
                    return SearchHit(relativePath: path, title: title, snippet: snip)
                }
            }
        } catch {
            // FTS5 parse errors (even after sanitization) must never surface to UI
            return []
        }
    }

    // MARK: - Query sanitization

    /// Rewrites `raw` as a safe FTS5 prefix query: each whitespace-separated token
    /// becomes `"token"*`. FTS5 special characters are stripped so the expression
    /// can never produce a syntax error.
    static func sanitize(_ raw: String) -> String {
        let words = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }
        return words
            .compactMap { word -> String? in
                let safe = word.filter { !"\"*:()-^".contains($0) }
                guard !safe.isEmpty else { return nil }
                return "\"\(safe)\"*"
            }
            .joined(separator: " ")
    }

    // MARK: - Private

    private static func dbURL(for vaultRoot: URL) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let indexDir = appSupport.appendingPathComponent("Flint/index")
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)
        let hash = SHA256.hash(data: Data(vaultRoot.path.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        return indexDir.appendingPathComponent("\(hash).sqlite")
    }

    private static func openOrRebuild(at url: URL) throws -> DatabaseQueue {
        do {
            let q = try DatabaseQueue(path: url.path)
            var needsRebuild = false
            try q.read { db in
                let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
                needsRebuild = (version != schemaVersion)
            }
            if needsRebuild {
                try q.write { db in
                    try db.execute(sql: "DROP TABLE IF EXISTS notes")
                    try createSchema(db)
                    try db.execute(sql: "PRAGMA user_version = \(schemaVersion)")
                }
            }
            return q
        } catch {
            // Corrupt or unrecognizable file — wipe and start clean.
            try? FileManager.default.removeItem(at: url)
            return try createFresh(at: url)
        }
    }

    private static func createFresh(at url: URL) throws -> DatabaseQueue {
        let q = try DatabaseQueue(path: url.path)
        try q.write { db in
            try createSchema(db)
            try db.execute(sql: "PRAGMA user_version = \(schemaVersion)")
        }
        return q
    }

    private static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS notes USING fts5(
                path UNINDEXED,
                title,
                body,
                mtime UNINDEXED,
                tokenize='unicode61'
            )
        """)
    }
}
