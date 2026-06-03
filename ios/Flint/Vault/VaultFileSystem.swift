// VaultFileSystem — coordinated, stateless disk access (files-as-truth).
//
// No app state here, only I/O. Every access is wrapped in NSFileCoordinator so
// we play nicely with iCloud/other-app writers and see a consistent file. These
// functions are synchronous and `nonisolated`; the iCloudDriveProvider calls them
// off the main actor (Task.detached). Since T2 these are the provider's private
// engine — no raw FileManager calls live above the SyncProvider layer.
import Foundation

enum VaultFileSystem {
    enum VaultError: LocalizedError {
        case coordination(Error)
        case invalidName
        case nameInUse(String)
        case invalidMove
        var errorDescription: String? {
            switch self {
            case .coordination(let e): return e.localizedDescription
            case .invalidName: return "Please enter a name."
            case .nameInUse(let n): return "“\(n)” already exists here."
            case .invalidMove: return "Can't move a folder into itself."
            }
        }
    }

    /// Recursively build the folder/`.md` tree under `root`. Hidden entries
    /// (dotfiles, `.obsidian`, `.trash`, …) are skipped. Folders are kept even
    /// when empty (they exist on disk; files-as-truth) — only non-`.md` files are
    /// omitted, since Phase 1 has no viewer for them.
    static func buildTree(root: URL) throws -> VaultNode {
        try coordinatedRead(root) { url in
            try node(at: url, isRoot: true) ?? VaultNode(
                url: url, name: url.lastPathComponent, isDirectory: true,
                modifiedAt: nil, createdAt: nil, children: []
            )
        }
    }

    /// Coordinated read of a note's UTF-8 text.
    static func readNote(at url: URL) throws -> String {
        try coordinatedRead(url) { try String(contentsOf: $0, encoding: .utf8) }
    }

    /// Create a new empty `.md` note in `directory`, picking a non-colliding name
    /// ("Untitled.md", "Untitled 1.md", …). Returns the created file's URL.
    static func createNote(in directory: URL, baseName: String = "Untitled") throws -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).md")
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).md")
            counter += 1
        }
        try writeNote("", to: candidate)
        return candidate
    }

    /// Create a new folder in `directory`, picking a non-colliding name
    /// ("New Folder", "New Folder 1", …). Returns the created folder's URL.
    static func createFolder(in directory: URL, baseName: String = "New Folder") throws -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(baseName)
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter)")
            counter += 1
        }
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: candidate, options: .forReplacing, error: &coordError) { dst in
            do { try fileManager.createDirectory(at: dst, withIntermediateDirectories: true) }
            catch { thrown = error }
        }
        if let coordError { throw VaultError.coordination(coordError) }
        if let thrown { throw thrown }
        return candidate
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

    /// Rename a note or folder in place. For notes the `.md` extension is kept
    /// regardless of what the user typed (the tree shows the bare stem). Returns
    /// the new URL. Throws `.nameInUse` rather than clobbering a sibling.
    static func rename(_ url: URL, to newBaseName: String) throws -> URL {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { throw VaultError.invalidName }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let dir = url.deletingLastPathComponent()
        let target = isDir
            ? dir.appendingPathComponent(trimmed)
            : dir.appendingPathComponent("\(trimmed).md")
        if target == url { return url }
        return try coordinatedMove(from: url, to: target)
    }

    /// Move a note or folder into `directory`, keeping its filename. Returns the
    /// new URL. Refuses to move a folder inside its own subtree.
    static func move(_ url: URL, into directory: URL) throws -> URL {
        let target = directory.appendingPathComponent(url.lastPathComponent)
        if target == url { return url }
        if directory.path == url.path || directory.path.hasPrefix(url.path + "/") {
            throw VaultError.invalidMove
        }
        return try coordinatedMove(from: url, to: target)
    }

    /// Delete a note or folder (coordinated). The UI confirms first.
    static func delete(_ url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { dst in
            do { try FileManager.default.removeItem(at: dst) }
            catch { thrown = error }
        }
        if let coordError { throw VaultError.coordination(coordError) }
        if let thrown { throw thrown }
    }

    // MARK: - Private

    /// Coordinated rename/move. Fails loudly if the destination is taken so an
    /// existing sibling is never overwritten.
    private static func coordinatedMove(from src: URL, to dst: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: dst.path) {
            throw VaultError.nameInUse(dst.deletingPathExtension().lastPathComponent)
        }
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var thrown: Error?
        coordinator.coordinate(
            writingItemAt: src, options: .forMoving,
            writingItemAt: dst, options: .forReplacing,
            error: &coordError
        ) { from, to in
            let fileManager = FileManager.default
            coordinator.item(at: from, willMoveTo: to)
            do {
                try fileManager.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch { thrown = error }
        }
        if let coordError { throw VaultError.coordination(coordError) }
        if let thrown { throw thrown }
        return dst
    }

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
        let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey]
        )
        let isDir = values?.isDirectory ?? false
        let modifiedAt = values?.contentModificationDate
        let createdAt = values?.creationDate

        if !isDir {
            guard url.pathExtension.lowercased() == "md" else { return nil }
            return VaultNode(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                isDirectory: false,
                modifiedAt: modifiedAt,
                createdAt: createdAt,
                children: nil
            )
        }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var children: [VaultNode] = []
        for entry in entries {
            if let child = try node(at: entry, isRoot: false) {
                children.append(child)
            }
        }

        // Folders are always shown — including empty ones — because the folder
        // exists on disk (files-as-truth) and matches Obsidian's behavior.
        // Expanding an empty folder simply reveals nothing.

        children.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }   // folders first
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        return VaultNode(
            url: url,
            name: url.lastPathComponent,
            isDirectory: true,
            modifiedAt: modifiedAt,
            createdAt: createdAt,
            children: children
        )
    }
}
