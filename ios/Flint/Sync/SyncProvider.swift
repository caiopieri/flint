// SyncProvider — the one abstraction every disk access goes through (T2).
//
// One consistency model (files-as-truth), multiple transports behind a protocol:
//   - iCloudDriveProvider (default, Phase 1): zero-server file sync + conflict
//     reconciliation (3-way merge / `.conflict` sibling).
//   - ServerProvider (optional, future): a dumb replication hub. NOT in Phase 1.
//
// Rule (ADR-003/004): no raw FileManager/NSFileCoordinator call lives ABOVE this
// layer. VaultStore and everything above depend only on `SyncProvider`, so a
// future transport slots in without touching the app.
import Foundation

/// The outcome of reconciling a file iCloud flagged as conflicted.
enum ConflictOutcome: Sendable, Equatable {
    /// No unresolved conflict versions existed — nothing to do.
    case none
    /// Reconciled cleanly: a trivial or 3-way merge was written to the file.
    case merged
    /// Could not merge fully; the other device's version was preserved in this
    /// sibling file so no edit is lost. The user reconciles it by hand.
    case conflictFile(URL)
}

/// A registered external-change watcher. Hold it for as long as you want the
/// callback; `cancel()` (or release) deregisters it.
protocol SyncWatch: Sendable {
    func cancel()
}

/// Files-as-truth disk access. Methods are async and run their blocking,
/// coordinated I/O off the main actor internally, so callers (`@MainActor`
/// stores) just `await`.
protocol SyncProvider: Sendable {
    /// Enumerate the folder/`.md` tree under the provider's root.
    func list() async throws -> VaultNode

    /// Read a note's text. Reconciles any pending iCloud conflict first, so the
    /// returned text already reflects a merge or a `.conflict` fallback.
    func read(_ url: URL) async throws -> String

    /// Write a note's text back (coordinated, atomic).
    func write(_ text: String, to url: URL) async throws

    /// Create a new empty `.md` note with a non-colliding name; returns its URL.
    func createNote(in directory: URL, baseName: String) async throws -> URL

    /// Create a new folder with a non-colliding name; returns its URL.
    func createFolder(in directory: URL, baseName: String) async throws -> URL

    /// Rename a note/folder in place; returns its new URL. Throws if the name is
    /// already taken (never overwrites a sibling).
    func rename(_ url: URL, to newBaseName: String) async throws -> URL

    /// Move a note/folder into another folder; returns its new URL.
    func move(_ url: URL, into directory: URL) async throws -> URL

    /// Delete a note/folder.
    func delete(_ url: URL) async throws

    /// Observe external changes (sync from another device, edits in Obsidian /
    /// Finder). The callback may arrive on any queue.
    func watch(_ onChange: @escaping @Sendable () -> Void) -> any SyncWatch

    /// Plain coordinated reads for the disposable search index. Unlike `read`, does
    /// NOT reconcile iCloud conflicts and does NOT advance the merge base — the index
    /// is derived and must observe content without perturbing sync state. Best-effort:
    /// unreadable files are omitted from the result, not thrown.
    func readForIndex(_ urls: [URL]) async throws -> [URL: String]

    /// Detect and reconcile iCloud conflict versions for one file. Never loses an
    /// edit: clean hunks merge into the file, anything ambiguous is preserved in
    /// a `.conflict` sibling.
    @discardableResult
    func resolveConflict(at url: URL) async throws -> ConflictOutcome
}
