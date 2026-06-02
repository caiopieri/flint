// VaultStore — observable, app-facing vault state (T1).
//
// Owns the security-scoped bookmark lifecycle (ADR-011), the in-memory tree, the
// currently open note, and the external-change watcher. UI reads this; all disk
// work is delegated to VaultFileSystem on a background task.
import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private(set) var rootURL: URL?
    private(set) var tree: VaultNode?
    private(set) var selection: VaultNode?
    private(set) var noteText: String?
    var errorMessage: String?

    var hasVault: Bool { rootURL != nil }

    private let bookmarkKey = "flint.vault.bookmark"
    private var accessedURL: URL?
    private var presenter: VaultPresenter?
    private var reloadTask: Task<Void, Never>?

    init() {
        restoreSavedVault()
    }

    // MARK: - Choosing / restoring the vault

    /// Open a folder the user just picked. The picker grants access; we persist a
    /// bookmark so the choice survives relaunch.
    func openVault(at url: URL) {
        saveBookmark(for: url)
        beginAccess(to: url)
        scheduleReload()
    }

    /// Forget the current vault (used by "Change vault folder").
    func closeVault() {
        stopAccess()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        rootURL = nil
        tree = nil
        selection = nil
        noteText = nil
    }

    private func restoreSavedVault() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            beginAccess(to: url)
            if isStale { saveBookmark(for: url) }   // re-persist the refreshed bookmark
            scheduleReload()
        } catch {
            errorMessage = "Couldn't reopen the saved vault. Choose it again."
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    private func saveBookmark(for url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            errorMessage = "Couldn't remember this folder: \(error.localizedDescription)"
        }
    }

    private func beginAccess(to url: URL) {
        stopAccess()
        _ = url.startAccessingSecurityScopedResource()
        accessedURL = url
        rootURL = url
        startWatching(url)
    }

    private func stopAccess() {
        stopWatching()
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    // MARK: - Loading the tree

    /// Coalesce bursts of external changes into a single reload.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    func reload() async {
        guard let url = rootURL else { return }
        do {
            let newTree = try await Task.detached(priority: .userInitiated) {
                try VaultFileSystem.buildTree(root: url)
            }.value
            tree = newTree
            errorMessage = nil
            // Refresh the open note if it still exists; drop it otherwise.
            if let selection {
                if FileManager.default.fileExists(atPath: selection.url.path) {
                    await open(selection)
                } else {
                    self.selection = nil
                    self.noteText = nil
                }
            }
        } catch {
            errorMessage = "Couldn't read the vault: \(error.localizedDescription)"
        }
    }

    // MARK: - Opening a note

    func open(_ node: VaultNode) async {
        guard !node.isDirectory else { return }
        selection = node
        do {
            let url = node.url
            let text = try await Task.detached(priority: .userInitiated) {
                try VaultFileSystem.readNote(at: url)
            }.value
            noteText = text
        } catch {
            noteText = nil
            errorMessage = "Couldn't open \(node.name): \(error.localizedDescription)"
        }
    }

    /// Create a new note at the vault root, then select and open it.
    func createNote() async {
        guard let root = rootURL else { return }
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try VaultFileSystem.createNote(in: root)
            }.value
            await reload()
            if let node = findNode(url, in: tree) { await open(node) }
        } catch {
            errorMessage = "Couldn't create a note: \(error.localizedDescription)"
        }
    }

    private func findNode(_ url: URL, in node: VaultNode?) -> VaultNode? {
        guard let node else { return nil }
        if node.url == url { return node }
        for child in node.children ?? [] {
            if let found = findNode(url, in: child) { return found }
        }
        return nil
    }

    // MARK: - External-change watching (NSFilePresenter)

    private func startWatching(_ url: URL) {
        let presenter = VaultPresenter(url: url) { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        self.presenter = presenter
        NSFileCoordinator.addFilePresenter(presenter)
    }

    private func stopWatching() {
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            self.presenter = nil
        }
    }
}
