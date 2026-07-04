// VaultStore — observable, app-facing vault state (T1).
//
// Owns the security-scoped bookmark lifecycle (ADR-011), the recent-vaults list,
// the in-memory tree, the currently open note, and the external-change watcher.
// UI reads this; all disk work is delegated to a SyncProvider (T2) — the store
// never touches FileManager/NSFileCoordinator itself.
import Foundation
import Observation

@MainActor
@Observable
final class VaultStore {
    private(set) var rootURL: URL?
    private(set) var tree: VaultNode?
    private(set) var selection: VaultNode?
    private(set) var recents: [RecentVaultRef] = []
    private(set) var inkRequest: String?
    private(set) var isLoadingTree = false
    var errorMessage: String?

    /// The selected note's path relative to the vault root — what the editor
    /// loads/saves over the bridge. `nil` when nothing (or a folder) is selected.
    /// Paths cross the bridge relative, never absolute (keeps the filesystem
    /// layout out of the webview; aligns with the future plugin capability model).
    var selectedRelativePath: String? {
        guard let root = rootURL, let selection, !selection.isDirectory else { return nil }
        return Self.relativePath(of: selection.url, under: root)
    }

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

    /// Current search query. Bind to the sidebar search field; set to "" to clear.
    var searchQuery: String = ""
    /// Ranked results for the current `searchQuery`. Empty when not searching.
    private(set) var searchResults: [SearchHit] = []
    /// True while the user has typed a non-empty search query.
    var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Tags (T5)

    /// path → sorted tag list, built incrementally from the index. Rehydrated from
    /// the FTS body column on relaunch so re-crawling the vault is never needed.
    private(set) var tagsByPath: [String: [String]] = [:]
    /// All unique tags across the vault, deduplicated case-insensitively, sorted.
    var allTags: [String] {
        var seen: [String: String] = [:]
        for tags in tagsByPath.values {
            for tag in tags {
                let key = tag.lowercased()
                if seen[key] == nil { seen[key] = tag }
            }
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    /// The currently filtered tag. Exclusive with `searchQuery` (D5).
    private(set) var activeTag: String?
    /// Notes that carry `activeTag`, ordered by the current `sortOrder`.
    var notesForActiveTag: [VaultNode] {
        guard let tag = activeTag, let root = rootURL, let treeRoot = tree else { return [] }
        let nodes = tagsByPath.compactMap { (path, tags) -> VaultNode? in
            guard tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return nil }
            return findNode(root.appendingPathComponent(path), in: treeRoot)
        }
        return sortedChildren(nodes)
    }

    /// Select (or deselect) a tag filter. Clears the search query (D5).
    func selectTag(_ tag: String) {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
        activeTag = (activeTag?.caseInsensitiveCompare(tag) == .orderedSame) ? nil : tag
    }

    private let bookmarkKey = "flint.vault.bookmark"
    private let recentsKey = "flint.vault.recents"
    private let sortKey = "flint.vault.sort"
    private let recentsLimit = 8
    private var accessedURL: URL?
    private var provider: (any SyncProvider)?
    private var watch: (any SyncWatch)?
    private var reloadTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchIndex: SearchIndex?

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
        let provider = iCloudDriveProvider(root: url)
        self.provider = provider
        watch = provider.watch { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        searchIndex = try? SearchIndex(vaultRoot: url)
    }

    private func stopAccess() {
        indexTask?.cancel()
        indexTask = nil
        searchTask?.cancel()
        searchTask = nil
        searchIndex = nil   // closes the DatabaseQueue
        searchQuery = ""
        searchResults = []
        tagsByPath = [:]
        activeTag = nil
        watch?.cancel()
        watch = nil
        provider = nil
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
        guard let provider else { return }
        isLoadingTree = true
        do {
            let newTree = try await provider.list()
            tree = newTree
            errorMessage = nil
            isLoadingTree = false
            // Keep the open note selected if it still exists. We deliberately do
            // NOT re-read it here: the editor owns the live buffer, and clobbering
            // it on an external refresh would drop the user's unsaved edits. A
            // truly divergent external change surfaces via the conflict path (T2)
            // on the next load.
            if let selection, findNode(selection.url, in: newTree) == nil {
                self.selection = nil
            }
            scheduleIndexSync()
        } catch {
            isLoadingTree = false
            errorMessage = "Couldn't read the vault: \(error.localizedDescription)"
        }
    }

    // MARK: - Search index sync

    /// Coalesces rapid reloads into a single background index pass.
    private func scheduleIndexSync() {
        indexTask?.cancel()
        indexTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.performIndexSync()
        }
    }

    private func performIndexSync() async {
        guard let index = searchIndex,
              let provider = provider,
              let root = rootURL,
              let tree = tree else { return }

        let flat = flattenNotes(tree, root: root)
        guard !Task.isCancelled else { return }

        do {
            let (toReadPaths, toDelete) = try await index.diff(current: flat)
            guard !Task.isCancelled else { return }

            let toReadURLs = toReadPaths.compactMap { root.appendingPathComponent($0) }
            let texts = try await provider.readForIndex(toReadURLs)
            guard !Task.isCancelled else { return }

            let mtimeByPath = Dictionary(flat.map { ($0.path, $0.mtime) }, uniquingKeysWith: { _, b in b })
            let upserts: [(path: String, title: String, mtime: Date, body: String)] =
                toReadURLs.compactMap { url in
                    guard let body = texts[url] else { return nil }
                    let rel = Self.relativePath(of: url, under: root)
                    let title = url.deletingPathExtension().lastPathComponent
                    let mtime = mtimeByPath[rel] ?? Date()
                    return (rel, title, mtime, body)
                }

            try await index.apply(upserts: upserts, deletes: toDelete)
            guard !Task.isCancelled else { return }

            // Incremental tag update from the just-indexed content.
            for path in toDelete { tagsByPath.removeValue(forKey: path) }
            for item in upserts { tagsByPath[item.path] = Frontmatter.tags(in: item.body) }

            // Relaunch: index already had data but nothing changed → tag map is still
            // empty (no upserts ran). Rehydrate from the stored bodies off-main.
            if tagsByPath.isEmpty && !flat.isEmpty {
                let rows = try await index.tagSource()
                let map = await Task.detached(priority: .utility) {
                    var result: [String: [String]] = [:]
                    for (path, body) in rows { result[path] = Frontmatter.tags(in: body) }
                    return result
                }.value
                guard !Task.isCancelled else { return }
                tagsByPath = map
            }
        } catch {
            // Index sync is best-effort — a failure just means slightly stale results.
        }
    }

    private func flattenNotes(_ node: VaultNode, root: URL) -> [(path: String, mtime: Date)] {
        var result: [(String, Date)] = []
        if !node.isDirectory, node.url.pathExtension.lowercased() == "md" {
            result.append((Self.relativePath(of: node.url, under: root), node.modifiedAt ?? Date()))
        }
        for child in node.children ?? [] {
            result.append(contentsOf: flattenNotes(child, root: root))
        }
        return result
    }

    // MARK: - Search

    /// Debounced: call on every `searchQuery` change. Clears results immediately
    /// when the query is empty; otherwise waits 200 ms before querying the index.
    /// A non-empty query clears the active tag (D5: search and tag filter are exclusive).
    func runSearch() {
        searchTask?.cancel()
        if isSearching { activeTag = nil }
        guard isSearching else {
            searchResults = []
            return
        }
        let q = searchQuery
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            await self.executeSearch(q)
        }
    }

    private func executeSearch(_ q: String) async {
        guard let index = searchIndex else { searchResults = []; return }
        do {
            searchResults = try await index.query(q)
        } catch {
            searchResults = []
        }
    }

    /// Resolve a search hit to a vault node and open it in the editor.
    func openHit(_ hit: SearchHit) {
        guard let root = rootURL else { return }
        let url = root.appendingPathComponent(hit.relativePath)
        if let node = findNode(url, in: tree) { open(node) }
    }

    // MARK: - Opening / creating notes

    /// Select a note. The editor reacts to `selectedRelativePath` and pulls the
    /// text over the bridge (`doc.load`); the store no longer reads it eagerly.
    func open(_ node: VaultNode) {
        guard !node.isDirectory else { return }
        selection = node
    }

    /// Load a note's text for the editor (bridge `doc.load`). Path is vault-relative.
    func editorLoad(_ relativePath: String) async throws -> String {
        guard let provider, let url = resolve(relativePath) else { throw VaultStoreError.noVault }
        return try await provider.read(url)
    }

    /// Persist a note's text from the editor (bridge `doc.save`). Path is vault-relative.
    func editorSave(_ relativePath: String, _ text: String) async throws {
        guard let provider, let url = resolve(relativePath) else { throw VaultStoreError.noVault }
        try await provider.write(text, to: url)
    }

    func notebookLoad(_ relativePath: String) async throws -> InkNotebook {
        guard let provider, let url = resolve(relativePath) else { throw VaultStoreError.noVault }
        return try InkNotebook.decode(try await provider.readData(url))
    }

    func notebookSave(_ relativePath: String, _ notebook: InkNotebook) async throws {
        guard let provider, let url = resolve(relativePath) else { throw VaultStoreError.noVault }
        try await provider.writeData(try notebook.encoded(), to: url)
    }

    func requestInk(_ target: String) {
        guard let path = resolveInkTarget(target) else {
            errorMessage = "Drawing not found: \(target)"
            return
        }
        inkRequest = path
    }

    func clearInkRequest() {
        inkRequest = nil
    }

    func resolveInkTarget(_ target: String) -> String? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let root = rootURL, let tree else { return nil }

        let normalized = trimmed.hasSuffix(".ink") ? trimmed : "\(trimmed).ink"
        if normalized.contains("/") {
            let url = root.appendingPathComponent(normalized)
            guard let node = findNode(url, in: tree), node.url.pathExtension.lowercased() == "ink" else { return nil }
            return Self.relativePath(of: node.url, under: root)
        }

        let matches = inkNodes(in: tree).filter { $0.url.lastPathComponent == normalized }
        guard matches.count == 1, let match = matches.first else { return nil }
        return Self.relativePath(of: match.url, under: root)
    }

    func inkThumbnailPNG(_ target: String) async -> Data? {
        guard let provider, let path = resolveInkTarget(target), let url = resolve(path) else { return nil }
        do {
            let notebook = try InkNotebook.decode(try await provider.readData(url))
            guard let first = notebook.pages.first else { return nil }
            return try InkRenderer.pagePNG(first, maxSize: CGSize(width: 320, height: 220), scale: 2)
        } catch {
            return nil
        }
    }

    /// Create a new note at the vault root, then select and open it.
    func createNote() async {
        guard let provider, let root = rootURL else { return }
        do {
            let url = try await provider.createNote(in: root, baseName: "Untitled")
            let node = optimisticFileNode(url)
            insertOptimisticRootChild(node)
            open(node)
            scheduleReload()
        } catch {
            errorMessage = "Couldn't create a note: \(error.localizedDescription)"
        }
    }

    func createDrawing() async {
        await createNotebook()
    }

    func createNotebook() async {
        guard let provider, let root = rootURL else { return }
        do {
            let url = try await provider.createInk(in: root, baseName: "Notebook")
            let node = optimisticFileNode(url)
            insertOptimisticRootChild(node)
            open(node)
            scheduleReload()
        } catch {
            errorMessage = "Couldn't create a notebook: \(error.localizedDescription)"
        }
    }

    /// Create a new folder at the vault root, then reload the tree.
    func createFolder() async {
        guard let provider, let root = rootURL else { return }
        do {
            let url = try await provider.createFolder(in: root, baseName: "New Folder")
            insertOptimisticRootChild(VaultNode(
                url: url,
                name: url.lastPathComponent,
                isDirectory: true,
                modifiedAt: nil,
                createdAt: nil,
                children: []
            ))
            scheduleReload()
        } catch {
            errorMessage = "Couldn't create a folder: \(error.localizedDescription)"
        }
    }

    // MARK: - Rename / move / delete

    /// Rename a note or folder. Keeps it selected if it was the open note.
    func rename(_ node: VaultNode, to newName: String) async {
        guard let provider else { return }
        do {
            let newURL = try await provider.rename(node.url, to: newName)
            let wasSelected = selection?.url == node.url
            await reload()
            if wasSelected, let moved = findNode(newURL, in: tree) { selection = moved }
        } catch {
            errorMessage = "Couldn't rename: \(error.localizedDescription)"
        }
    }

    /// Move a note or folder into `directory` (a folder node).
    func move(_ node: VaultNode, into directory: VaultNode) async {
        guard let provider, directory.isDirectory else { return }
        do {
            let newURL = try await provider.move(node.url, into: directory.url)
            let wasSelected = selection?.url == node.url
            await reload()
            if wasSelected, let moved = findNode(newURL, in: tree) { selection = moved }
        } catch {
            errorMessage = "Couldn't move: \(error.localizedDescription)"
        }
    }

    /// Delete a note or folder. Clears the selection if it was the open note.
    func delete(_ node: VaultNode) async {
        guard let provider else { return }
        do {
            try await provider.delete(node.url)
            if selection?.url == node.url { selection = nil }
            await reload()
        } catch {
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
        }
    }

    /// Find a node by its URL anywhere in the current tree (used by drag-drop).
    func node(at url: URL) -> VaultNode? { findNode(url, in: tree) }

    private func inkNodes(in node: VaultNode) -> [VaultNode] {
        var result: [VaultNode] = []
        if !node.isDirectory, node.url.pathExtension.lowercased() == "ink" {
            result.append(node)
        }
        for child in node.children ?? [] {
            result.append(contentsOf: inkNodes(in: child))
        }
        return result
    }

    private func optimisticFileNode(_ url: URL) -> VaultNode {
        VaultNode(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            isDirectory: false,
            modifiedAt: Date(),
            createdAt: Date(),
            children: nil
        )
    }

    private func insertOptimisticRootChild(_ node: VaultNode) {
        guard var root = tree else { return }
        var children = root.children ?? []
        children.removeAll { $0.url == node.url }
        children.append(node)
        root.children = children
        tree = root
    }

    private func findNode(_ url: URL, in node: VaultNode?) -> VaultNode? {
        guard let node else { return nil }
        if node.url == url { return node }
        for child in node.children ?? [] {
            if let found = findNode(url, in: child) { return found }
        }
        return nil
    }

    // MARK: - Vault-relative path mapping (bridge <-> disk)

    /// Resolve a vault-relative path (from the editor) to an absolute URL.
    private func resolve(_ relativePath: String) -> URL? {
        rootURL?.appendingPathComponent(relativePath)
    }

    /// A file's path relative to the vault root, used as its bridge identity.
    static func relativePath(of url: URL, under root: URL) -> String {
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.lastPathComponent
    }
}

enum VaultStoreError: LocalizedError {
    case noVault
    var errorDescription: String? {
        switch self {
        case .noVault: return "No vault is open."
        }
    }
}
