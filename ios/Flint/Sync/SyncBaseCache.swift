// SyncBaseCache — disposable record of each note's last-synced content (T2.3).
//
// The 3-way merge needs a common ancestor, but iCloud does NOT preserve one: a
// conflict gives you "mine" and "theirs", never the version they diverged from.
// So Flint keeps its own ancestor: the last content we observed as SYNCED for a
// file. It lives in Application Support (a Flint-private cache), is keyed by the
// note's path within the vault, and is fully disposable — like the search index,
// never a source of truth. If it's missing, the provider degrades to a safe
// 2-way comparison.
//
// Update discipline (important, enforced by the provider): the base tracks
// SYNC-delivered content and merge results — NOT local saves. Advancing it on a
// local edit would make `base == mine`, which the merge reads as "mine didn't
// change" and would silently drop the local edit. When the editor lands (T3),
// its writes must still leave the base alone; only sync updates it.
import CryptoKit
import Foundation

struct SyncBaseCache: Sendable {
    private let root: URL
    private let directory: URL

    init(root: URL) {
        self.root = root
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // One subfolder per vault so distinct vaults don't collide.
        self.directory = support
            .appendingPathComponent("Flint/SyncBase", isDirectory: true)
            .appendingPathComponent(Self.key(for: root.path), isDirectory: true)
    }

    /// Last-synced content for a file, or nil if we have no ancestor for it.
    func base(for url: URL) -> String? {
        try? String(contentsOf: location(for: url), encoding: .utf8)
    }

    /// Record `text` as the new common ancestor for `url`. Best-effort: a cache
    /// write failing must never block real vault I/O (the merge just degrades to
    /// 2-way next time).
    func update(_ text: String, for url: URL) {
        let dst = location(for: url)
        try? FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.data(using: .utf8)?.write(to: dst, options: .atomic)
    }

    /// Drop a file's ancestor (e.g. after delete). Best-effort.
    func forget(_ url: URL) {
        try? FileManager.default.removeItem(at: location(for: url))
    }

    // MARK: - Private

    /// Map a vault file to its cache file, keyed by the note's path relative to
    /// the vault root (so moving the vault folder doesn't matter; renaming a note
    /// just creates a fresh, empty ancestor — safe, falls back to 2-way).
    private func location(for url: URL) -> URL {
        let relative = url.path.hasPrefix(root.path)
            ? String(url.path.dropFirst(root.path.count))
            : url.path
        return directory.appendingPathComponent(Self.key(for: relative))
    }

    private static func key(for string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
