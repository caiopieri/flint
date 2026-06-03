// iCloudDriveProvider — the Phase 1 SyncProvider (T2.2 + T2.3).
//
// "Sync" here is whatever the user's chosen folder already has (iCloud Drive,
// Finder, Working Copy, …): files are canonical per device, and iCloud moves
// them. This provider wraps the coordinated disk primitives (VaultFileSystem),
// watches for external changes (VaultPresenter), and reconciles iCloud conflict
// versions — 3-way merge when an ancestor exists (SyncBaseCache), a `.conflict`
// sibling otherwise. It never silently loses an edit.
//
// Immutable (root + cache) → safely Sendable. Blocking, coordinated I/O runs off
// the main actor via Task.detached so `@MainActor` callers just `await`.
import Foundation

final class iCloudDriveProvider: SyncProvider {
    private let root: URL
    private let baseCache: SyncBaseCache

    init(root: URL) {
        self.root = root
        self.baseCache = SyncBaseCache(root: root)
    }

    // MARK: - Reads / writes

    func list() async throws -> VaultNode {
        let root = self.root
        return try await Task.detached(priority: .userInitiated) {
            try VaultFileSystem.buildTree(root: root)
        }.value
    }

    func read(_ url: URL) async throws -> String {
        // Reconcile any pending conflict first so callers always see merged text.
        _ = try? await resolveConflict(at: url)
        let cache = baseCache
        return try await Task.detached(priority: .userInitiated) {
            let text = try VaultFileSystem.readNote(at: url)
            // A plain read in Phase 1 reflects synced content (no local editor yet
            // writes here), so it's a valid ancestor. T3 must NOT advance the base
            // on the editor's own saves — see SyncBaseCache.
            cache.update(text, for: url)
            return text
        }.value
    }

    func write(_ text: String, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try VaultFileSystem.writeNote(text, to: url)
            // Deliberately NOT updating the base here: a local save is not yet a
            // common version. Advancing the ancestor on local edits would make the
            // merge drop the edit.
        }.value
    }

    func createNote(in directory: URL, baseName: String) async throws -> URL {
        let cache = baseCache
        return try await Task.detached(priority: .userInitiated) {
            let url = try VaultFileSystem.createNote(in: directory, baseName: baseName)
            cache.update("", for: url)   // brand-new file: empty common ancestor
            return url
        }.value
    }

    func createFolder(in directory: URL, baseName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try VaultFileSystem.createFolder(in: directory, baseName: baseName)
        }.value
    }

    // MARK: - Rename / move / delete

    func rename(_ url: URL, to newBaseName: String) async throws -> URL {
        let cache = baseCache
        return try await Task.detached(priority: .userInitiated) {
            let newURL = try VaultFileSystem.rename(url, to: newBaseName)
            cache.forget(url)   // the ancestor was keyed by the old path
            return newURL
        }.value
    }

    func move(_ url: URL, into directory: URL) async throws -> URL {
        let cache = baseCache
        return try await Task.detached(priority: .userInitiated) {
            let newURL = try VaultFileSystem.move(url, into: directory)
            cache.forget(url)
            return newURL
        }.value
    }

    func delete(_ url: URL) async throws {
        let cache = baseCache
        try await Task.detached(priority: .userInitiated) {
            try VaultFileSystem.delete(url)
            cache.forget(url)
        }.value
    }

    // MARK: - Watching

    func watch(_ onChange: @escaping @Sendable () -> Void) -> any SyncWatch {
        FilePresenterWatch(url: root, onChange: onChange)
    }

    // MARK: - Conflict reconciliation

    func resolveConflict(at url: URL) async throws -> ConflictOutcome {
        let cache = baseCache
        return try await Task.detached(priority: .userInitiated) {
            guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
                  !versions.isEmpty else {
                return ConflictOutcome.none
            }

            let mine = try VaultFileSystem.readNote(at: url)
            let theirsAll = versions.compactMap { try? VaultFileSystem.readNote(at: $0.url) }
            guard let theirs = theirsAll.first else {
                // Couldn't read the other versions — leave them unresolved rather
                // than risk losing them.
                return ConflictOutcome.none
            }

            // Decide the merged content + whether anything must be preserved aside.
            let merged: String
            let preserve: Bool
            if let base = cache.base(for: url) {
                let result = Diff3.merge(base: base, mine: mine, theirs: theirs)
                merged = result.text          // clean hunks already folded in
                preserve = result.hadConflict // conflicting hunks → keep theirs aside
            } else {
                // No ancestor: a safe 2-way. Identical content is no real conflict;
                // otherwise keep mine in place and preserve theirs.
                merged = mine
                preserve = (mine != theirs)
            }

            if merged != mine {
                try VaultFileSystem.writeNote(merged, to: url)
            }

            // Preserve every version we didn't fully fold in, so nothing is lost.
            var sibling: URL?
            let toPreserve = preserve ? theirsAll : Array(theirsAll.dropFirst())
            for content in toPreserve {
                if let s = try? Self.writeConflictSibling(content, for: url), sibling == nil {
                    sibling = s
                }
            }

            // Tell iCloud the conflict is handled, then collapse stored versions.
            for version in versions { version.isResolved = true }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)

            // The reconciled on-disk content is the new common ancestor.
            cache.update(merged, for: url)

            if let sibling { return .conflictFile(sibling) }
            return .merged
        }.value
    }

    /// Write `content` to a visible `.md` sibling so the user can reconcile it by
    /// hand. Named "<note>.conflict.md" (then " 1", " 2", … on collision).
    private static func writeConflictSibling(_ content: String, for url: URL) throws -> URL {
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(stem).conflict.md")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem).conflict \(counter).md")
            counter += 1
        }
        try VaultFileSystem.writeNote(content, to: candidate)
        return candidate
    }
}

/// `SyncWatch` backed by an `NSFilePresenter`. Registers on init, deregisters on
/// cancel/deinit. Idempotent: NSFileCoordinator tolerates removing a presenter
/// that's already gone.
private final class FilePresenterWatch: SyncWatch, @unchecked Sendable {
    private let presenter: VaultPresenter

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.presenter = VaultPresenter(url: url, onChange: onChange)
        NSFileCoordinator.addFilePresenter(presenter)
    }

    func cancel() {
        NSFileCoordinator.removeFilePresenter(presenter)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(presenter)
    }
}
