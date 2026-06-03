// Vault — files-as-truth I/O.
//
// The files ARE the source of truth — never a database. This module enumerates
// and reads/writes `.md` files in the user-chosen vault folder via
// NSFileCoordinator/NSFilePresenter, reached through a security-scoped bookmark
// (ADR-011). Since T2 this disk access is reached through a SyncProvider — the
// store talks to the provider, the provider uses these coordinated primitives.
//
// Layout:
//   - VaultNode        (here)            the folder/file tree model
//   - VaultStore       (VaultStore)      observable app-facing state (→ SyncProvider)
//   - VaultFileSystem  (VaultFileSystem) coordinated disk primitives (provider's engine)
//   - VaultPresenter   (VaultPresenter)  external-change watcher (used by the provider)
import Foundation

/// A node in the vault tree: a folder or a `.md` file. Value type, Sendable so
/// it can cross from the background I/O task to the main actor freely.
struct VaultNode: Identifiable, Hashable, Sendable {
    let url: URL
    /// Display name. For `.md` files the extension is stripped.
    let name: String
    let isDirectory: Bool
    /// File-system dates, used by the sidebar's sort control. May be nil if the
    /// volume doesn't report them.
    let modifiedAt: Date?
    let createdAt: Date?
    /// `nil` for files (no disclosure triangle); a (possibly empty) array for
    /// folders — empty folders are shown and expand to reveal nothing.
    var children: [VaultNode]?

    var id: URL { url }
}
