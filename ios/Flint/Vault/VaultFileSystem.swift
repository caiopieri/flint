// VaultFileSystem — coordinated, stateless disk access (files-as-truth).
//
// No app state here, only I/O. Every access is wrapped in NSFileCoordinator so
// we play nicely with iCloud/other-app writers and see a consistent file. These
// functions are synchronous and `nonisolated`; call them off the main actor
// (the store uses Task.detached). In T2 this becomes the iCloudDriveProvider
// behind the SyncProvider protocol — no raw FileManager calls leak past here.
import Foundation

enum VaultFileSystem {
    enum VaultError: LocalizedError {
        case coordination(Error)
        var errorDescription: String? {
            switch self {
            case .coordination(let e): return e.localizedDescription
            }
        }
    }

    /// Recursively build the folder/`.md` tree under `root`. Hidden entries
    /// (dotfiles, `.obsidian`, `.trash`, …) are skipped, and folders that end up
    /// holding no notes are pruned so the navigator stays clean.
    static func buildTree(root: URL) throws -> VaultNode {
        try coordinatedRead(root) { url in
            try node(at: url, isRoot: true) ?? VaultNode(
                url: url, name: url.lastPathComponent, isDirectory: true, children: []
            )
        }
    }

    /// Coordinated read of a note's UTF-8 text.
    static func readNote(at url: URL) throws -> String {
        try coordinatedRead(url) { try String(contentsOf: $0, encoding: .utf8) }
    }

    /// Coordinated, atomic write-back of a note's text. (Wired by the editor in T3.)
    static func writeNote(_ text: String, to url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { dst in
            do { try text.data(using: .utf8)?.write(to: dst, options: .atomic) }
            catch { thrown = error }
        }
        if let coordError { throw VaultError.coordination(coordError) }
        if let thrown { throw thrown }
    }

    // MARK: - Private

    private static func coordinatedRead<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { src in
            result = Result { try body(src) }
        }
        if let coordError { throw VaultError.coordination(coordError) }
        guard let result else { throw VaultError.coordination(NSError(domain: "Flint.Vault", code: -1)) }
        return try result.get()
    }

    /// Build one node. Returns nil for a directory subtree that contains no notes
    /// (so the caller can prune it).
    private static func node(at url: URL, isRoot: Bool) throws -> VaultNode? {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        if !isDir {
            guard url.pathExtension.lowercased() == "md" else { return nil }
            return VaultNode(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                isDirectory: false,
                children: nil
            )
        }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var children: [VaultNode] = []
        for entry in entries {
            if let child = try node(at: entry, isRoot: false) {
                children.append(child)
            }
        }

        // Prune folders that hold no notes anywhere in their subtree.
        if !isRoot && children.isEmpty { return nil }

        children.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }   // folders first
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        return VaultNode(
            url: url,
            name: url.lastPathComponent,
            isDirectory: true,
            children: children
        )
    }
}
