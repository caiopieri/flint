// VaultStore — observable, app-facing vault state (T1).
//
// Owns the security-scoped bookmark lifecycle (ADR-011), the recent-vaults list,
// the in-memory tree, the currently open note, and the external-change watcher.
// UI reads this; all disk work is delegated to VaultFileSystem on a background task.
import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private(set) var rootURL: URL?
    private(set) var tree: VaultNode?
    private(set) var selection: VaultNode?
    private(set) var noteText: String?
    private(set) var recents: [RecentVaultRef] = []
    var errorMessage: String?

    /// How the file tree is ordered. Persisted; applied at display time so
    /// switching is instant (no disk reload). Folders always come before files.
    var sortOrder: VaultSort = .nameAsc {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: sortKey) }
    }

    /// The orderings offered by the sidebar's sort menu.
    enum VaultSort: String, CaseIterable, Identifiable, Sendable {
        case nameAsc, nameDesc
        case modifiedDesc, modifiedAsc
        case createdDesc, createdAsc

        var id: String { rawValue }
        var label: String {
            switch self {
            case .nameAsc:      return "Name (A–Z)"
            case .nameDesc:     return "Name (Z–A)"
            case .modifiedDesc: return "Modified (newest first)"
            case .modifiedAsc:  return "Modified (oldest first)"
            case .createdDesc:  return "Created (newest first)"
            case .createdAsc:   return "Created (oldest first)"
            }
        }
    }

    var hasVault: Bool { rootURL != nil }

    /// Sort one level of the tree by the current order, folders always first.
    func sortedChildren(_ nodes: [VaultNode]) -> [VaultNode] {
        nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sortOrder {
            case .nameAsc:      return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .nameDesc:     return a.name.localizedStandardCompare(b.name) == .orderedDescending
            case .modifiedDesc: return (a.modifiedAt ?? .distantPast) > (b.modifiedAt ?? .distantPast)
            case .modifiedAsc:  return (a.modifiedAt ?? .distantPast) < (b.modifiedAt ?? .distantPast)
            case .createdDesc:  return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            case .createdAsc:   return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
            }
        }
    }

    /// A previously-opened vault, resolvable from its security-scoped bookmark.
    struct RecentVaultRef: Identifiable, Hashable, Sendable {
        let id: String      // the folder path — stable across launches
        let name: String
        let bookmark: Data
    }

    private let bookmarkKey = "flint.vault.bookmark"
    private let recentsKey = "flint.vault.recents"
    private let sortKey = "flint.vault.sort"
    private let recentsLimit = 8
    private var accessedURL: URL?
    private var presenter: VaultPresenter?
    private var reloadTask: Task<Void, Never>?

    init() {
        if let raw = UserDefaults.standard.string(forKey: sortKey),
           let saved = VaultSort(rawValue: raw) {
            sortOrder = saved
        }
        loadRecents()
        restoreSavedVault()
    }

    // MARK: - Choosing / restoring / switching the vault

    /// Open a folder the user just picked. The picker grants access; we persist a
    /// bookmark so the choice survives relaunch and add it to recents.
    func openVault(at url: URL) {
        if let data = saveBookmark(for: url) { addRecent(data, url: url) }
        beginAccess(to: url)
        selection = nil
        noteText = nil
        scheduleReload()
    }

    /// Switch to a previously-opened vault from the recents list.
    func openRecent(_ ref: RecentVaultRef) {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: ref.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            errorMessage = "Couldn't open “\(ref.name)”. It may have moved."
            removeRecent(ref)
            return
        }
        beginAccess(to: url)
        if isStale, let fresh = saveBookmark(for: url) {
            addRecent(fresh, url: url)
        } else {
            UserDefaults.standard.set(ref.bookmark, forKey: bookmarkKey)
            addRecent(ref.bookmark, url: url)   // promote to front
        }
        selection = nil
        noteText = nil
        scheduleReload()
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
            if isStale, let fresh = saveBookmark(for: url) {
                addRecent(fresh, url: url)
            } else {
                addRecent(data, url: url)
            }
            scheduleReload()
        } catch {
            errorMessage = "Couldn't reopen the saved vault. Choose it again."
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    @discardableResult
    private func saveBookmark(for url: URL) -> Data? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            return data
        } catch {
            errorMessage = "Couldn't remember this folder: \(error.localizedDescription)"
            return nil
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

    // MARK: - Recents

    private func loadRecents() {
        let datas = (UserDefaults.standard.array(forKey: recentsKey) as? [Data]) ?? []
        recents = datas.compactMap { ref(from: $0) }
    }

    private func ref(from bookmark: Data) -> RecentVaultRef? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return RecentVaultRef(id: url.path, name: url.lastPathComponent, bookmark: bookmark)
    }

    private func addRecent(_ bookmark: Data, url: URL) {
        var list = recents.filter { $0.id != url.path }
        list.insert(RecentVaultRef(id: url.path, name: url.lastPathComponent, bookmark: bookmark), at: 0)
        if list.count > recentsLimit { list = Array(list.prefix(recentsLimit)) }
        recents = list
        UserDefaults.standard.set(list.map(\.bookmark), forKey: recentsKey)
    }

    private func removeRecent(_ ref: RecentVaultRef) {
        recents.removeAll { $0.id == ref.id }
        UserDefaults.standard.set(recents.map(\.bookmark), forKey: recentsKey)
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

    // MARK: - Opening / creating notes

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

    /// Create a new folder at the vault root, then reload the tree.
    func createFolder() async {
        guard let root = rootURL else { return }
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try VaultFileSystem.createFolder(in: root)
            }.value
            await reload()
        } catch {
            errorMessage = "Couldn't create a folder: \(error.localizedDescription)"
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
