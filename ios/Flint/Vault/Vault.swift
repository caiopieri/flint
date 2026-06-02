// Vault — files-as-truth I/O.
//
// The files ARE the source of truth — never a database. This module enumerates
// and reads/writes `.md` files in the user-chosen vault folder via
// NSFileCoordinator/NSFilePresenter, reached through a security-scoped bookmark
// (ADR-011). In T2 this access moves behind the SyncProvider abstraction.
//
// Layout:
//   - VaultNode        (here)            the folder/file tree model
//   - VaultFileSystem  (VaultFileSystem) coordinated, stateless disk I/O
//   - VaultStore       (VaultStore)      observable app-facing state
//   - VaultPresenter   (VaultPresenter)  external-change watcher
import Foundation

/// A node in the vault tree: a folder or a `.md` file. Value type, Sendable so
/// it can cross from the background I/O task to the main actor freely.
struct VaultNode: Identifiable, Hashable, Sendable {
    let url: URL
    /// Display name. For `.md` files the extension is stripped.
    let name: String
    let isDirectory: Bool
    /// `nil` for files and for pruned/empty folders (no disclosure triangle);
    /// a (possibly empty) array for folders that contain notes.
    var children: [VaultNode]?

    var id: URL { url }
}
