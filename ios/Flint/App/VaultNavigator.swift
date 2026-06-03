import SwiftUI

/// The app frame once a vault is open. Picks the right shell per width:
/// iPad/regular → the tree floats *over* the note (overlay with a light scrim);
/// iPhone/compact → a push drawer (the tree shoves the note aside). Both match
/// Obsidian: iPad has room to let the note stay full-width under an overlay,
/// the phone doesn't, so it pushes. Spec: docs/design/COMPONENTS.md → "Navigation shell · T1".
struct VaultNavigator: View {
    let vault: VaultStore
    var chooseVault: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            CompactNavigator(vault: vault, chooseVault: chooseVault)
        } else {
            RegularNavigator(vault: vault, chooseVault: chooseVault)
        }
    }
}

// MARK: - iPad / regular width

private struct RegularNavigator: View {
    let vault: VaultStore
    var chooseVault: () -> Void
    @State private var showSidebar = true
    private let sidebarWidth: CGFloat = 320

    // A hand-rolled overlay instead of NavigationSplitView: the iPadOS floating
    // sidebar injects its own toggle button that can't be reliably removed
    // (duplicate), and we want the tree to float *over* a full-width note, not
    // split it. Owning the layout gives exactly one toggle and full control.
    // Overlay (never push): the note stays full-width; the sidebar slides over it.
    // The open control is a real top-of-stack button, NOT a NavigationStack toolbar
    // item — under the overlay on iPad that toolbar button silently won't fire.
    var body: some View {
        ZStack(alignment: .topLeading) {
            NavigationStack {
                NoteDetail(vault: vault)
            }

            // Light scrim over the note while open; tap to dismiss. Inert when closed.
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .opacity(showSidebar ? 1 : 0)
                .allowsHitTesting(showSidebar)
                .onTapGesture { setSidebar(false) }

            // The sidebar slides over the content.
            SidebarContent(vault: vault, chooseVault: chooseVault, onSelectNote: { setSidebar(false) })
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(FlintColor.surface)
                // Structure via a hairline border, never a shadow (design system §4).
                .overlay(alignment: .trailing) { FlintColor.border.frame(width: 1) }
                .offset(x: showSidebar ? 0 : -sidebarWidth)
                .allowsHitTesting(showSidebar)

            // Open button — only while closed (the sidebar header owns the top-left
            // when open; close by tapping the scrim or a note). Topmost, so nothing
            // can swallow the tap.
            if !showSidebar {
                Button { setSidebar(true) } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.body)
                        .foregroundStyle(FlintColor.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.flintPressable)
                .padding(.leading, FlintSpace.s2)
                .transition(.opacity)
            }
        }
        .background(FlintColor.bg)
        .animation(.easeOut(duration: FlintMotion.base), value: showSidebar)
    }

    // Implicit `.animation(value:)` on the container drives both directions
    // reliably, so this just flips state — no withAnimation needed.
    private func setSidebar(_ open: Bool) {
        showSidebar = open
    }
}

// MARK: - iPhone / compact width — push drawer

private struct CompactNavigator: View {
    let vault: VaultStore
    var chooseVault: () -> Void
    @State private var isOpen = false

    var body: some View {
        GeometryReader { geo in
            let screenW = geo.size.width
            let sidebarW = min(screenW * 0.82, 340)

            HStack(spacing: 0) {
                SidebarContent(vault: vault, chooseVault: chooseVault, onSelectNote: { setOpen(false) })
                    .frame(width: sidebarW)
                    .overlay(alignment: .trailing) { FlintColor.border.frame(width: 1) }

                ZStack {
                    NavigationStack {
                        NoteDetail(vault: vault)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Files", systemImage: "sidebar.leading") { setOpen(!isOpen) }
                                }
                            }
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    // Tap/swipe the pushed-aside note to dismiss (no dimming —
                    // the tree pushes, it doesn't overlay).
                    if isOpen {
                        Color.clear
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { setOpen(false) }
                            .gesture(
                                DragGesture(minimumDistance: 20)
                                    .onEnded { if $0.translation.width < -40 { setOpen(false) } }
                            )
                    }
                }
                .frame(width: screenW)
                .overlay(alignment: .leading) {
                    if !isOpen {
                        Color.clear
                            .frame(width: 16)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 20)
                                    .onEnded { if $0.translation.width > 40 { setOpen(true) } }
                            )
                    }
                }
            }
            .frame(width: sidebarW + screenW, alignment: .leading)
            .offset(x: isOpen ? 0 : -sidebarW)
        }
        .background(FlintColor.surface.ignoresSafeArea())
        .onAppear { if vault.selection == nil { isOpen = true } }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(.easeOut(duration: FlintMotion.base)) { isOpen = open }
    }
}

// MARK: - Sidebar content (shared by both shells)

/// The vault name (tap → switch/open vault) + a new-note button, over the file tree.
private struct SidebarContent: View {
    let vault: VaultStore
    var chooseVault: () -> Void
    /// Lets the compact drawer close itself when a note is opened/created.
    var onSelectNote: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            FlintColor.border.frame(height: 1)
            if vault.tree?.children?.isEmpty ?? true {
                emptyState
            } else {
                VaultTreeList(vault: vault, onSelectNote: onSelectNote)
            }
        }
        .background(FlintColor.surface)
    }

    private var header: some View {
        HStack(spacing: FlintSpace.s2) {
            Menu {
                ForEach(vault.recents) { ref in
                    Button {
                        vault.openRecent(ref)
                    } label: {
                        Label(ref.name, systemImage: ref.id == vault.rootURL?.path ? "checkmark" : "folder")
                    }
                }
                if !vault.recents.isEmpty { Divider() }
                Button("Open another vault…", systemImage: "plus", action: chooseVault)
            } label: {
                HStack(spacing: FlintSpace.s1) {
                    Text(vault.tree?.name ?? "Vault")
                        .font(.headline)
                        .foregroundStyle(FlintColor.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(FlintColor.textMuted)
                }
            }
            .buttonStyle(.flintPressable)

            Spacer(minLength: 0)

            Menu {
                Picker("Sort by", selection: Binding(
                    get: { vault.sortOrder },
                    set: { vault.sortOrder = $0 }
                )) {
                    ForEach(VaultStore.VaultSort.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(FlintColor.textSecondary)
            .buttonStyle(.flintPressable)

            Button("New folder", systemImage: "folder.badge.plus") {
                Task { await vault.createFolder() }
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(FlintColor.textSecondary)
            .buttonStyle(.flintPressable)

            Button("New note", systemImage: "square.and.pencil") {
                onSelectNote?()
                Task { await vault.createNote() }
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(FlintColor.textSecondary)
            .buttonStyle(.flintPressable)
        }
        .padding(.horizontal, FlintSpace.s4)
        .padding(.vertical, FlintSpace.s3)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No notes yet", systemImage: "doc.text")
        } description: {
            Text("This folder has no Markdown notes.")
        } actions: {
            Button("New note") {
                onSelectNote?()
                Task { await vault.createNote() }
            }
            .buttonStyle(.flintPrimary)
            .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - The file tree

/// A LazyVStack driven by an explicit expansion set, so the **whole row** is the
/// tap target (folders toggle, files open) — not just the label text. Expanding
/// reveals children with a fade+slide and the chevron rotates, instead of the
/// abrupt row-pop the List gave.
private struct VaultTreeList: View {
    let vault: VaultStore
    var onSelectNote: (() -> Void)?
    @State private var expanded: Set<URL> = []
    @State private var renaming: VaultNode?
    @State private var renameText = ""
    @State private var deleting: VaultNode?
    @State private var dropTarget: URL?
    @FocusState private var renameFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(flattened(vault.sortedChildren(vault.tree?.children ?? []), depth: 0), id: \.node.id) { item in
                    row(item.node, depth: item.depth)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, FlintSpace.s2)
        }
        .background(FlintColor.surface)
        // Destructive delete always confirms first.
        .confirmationDialog(
            deleting.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let node = deleting { Task { await vault.delete(node) } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            if let node = deleting {
                Text(node.isDirectory
                    ? "This folder and its notes will be deleted."
                    : "This note will be deleted.")
            }
        }
    }

    private func flattened(_ nodes: [VaultNode], depth: Int) -> [(node: VaultNode, depth: Int)] {
        var rows: [(VaultNode, Int)] = []
        for node in nodes {
            rows.append((node, depth))
            if node.isDirectory, expanded.contains(node.url), let kids = node.children {
                rows.append(contentsOf: flattened(vault.sortedChildren(kids), depth: depth + 1))
            }
        }
        return rows
    }

    // The row plus its interactions: long-press → context menu (rename/delete),
    // drag → move; folder rows are drop targets that highlight while targeted.
    // iOS disambiguates press-and-hold (menu) from press-and-drag (move) natively.
    @ViewBuilder
    private func row(_ node: VaultNode, depth: Int) -> some View {
        if renaming?.id == node.id {
            renameRow(node, depth: depth)
        } else {
            let base = rowButton(node, depth: depth)
                .contextMenu {
                    Button("Rename", systemImage: "pencil") {
                        renameText = node.name
                        renaming = node
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleting = node
                    }
                }
                .draggable(node.url.absoluteString)

            if node.isDirectory {
                base.dropDestination(for: String.self) { items, _ in
                    handleDrop(items, into: node)
                } isTargeted: { targeted in
                    dropTarget = targeted ? node.url : (dropTarget == node.url ? nil : dropTarget)
                }
            } else {
                base
            }
        }
    }

    // Inline rename, Obsidian-style: the row's name becomes an editable field in
    // place (no modal). Commits on Return or when focus leaves (tap elsewhere);
    // an empty or unchanged name is a no-op.
    private func renameRow(_ node: VaultNode, depth: Int) -> some View {
        HStack(spacing: FlintSpace.s2) {
            Group {
                if node.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(FlintColor.textMuted)
                        .rotationEffect(.degrees(expanded.contains(node.url) ? 90 : 0))
                } else {
                    Color.clear
                }
            }
            .frame(width: 10)

            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(FlintColor.textSecondary)
                .frame(width: 20)

            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(FlintColor.textPrimary)
                .focused($renameFocused)
                .submitLabel(.done)
                .onSubmit { commitRename(node) }

            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * FlintSpace.s4 + FlintSpace.s4)
        .padding(.trailing, FlintSpace.s4)
        .padding(.vertical, FlintSpace.s2)
        .background(FlintColor.surfaceRaised)
        .onAppear { renameFocused = true }
        .onChange(of: renameFocused) { _, focused in
            if !focused { commitRename(node) }   // tapping away commits, like Obsidian
        }
    }

    private func commitRename(_ node: VaultNode) {
        guard renaming?.id == node.id else { return }   // already handled
        renaming = nil
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != node.name else { return }
        Task { await vault.rename(node, to: trimmed) }
    }

    /// Move dropped node(s) into `folder`. The payload is a node's URL string.
    private func handleDrop(_ items: [String], into folder: VaultNode) -> Bool {
        guard let raw = items.first,
              let url = URL(string: raw),
              let node = vault.node(at: url) else { return false }
        Task { await vault.move(node, into: folder) }
        return true
    }

    private func rowButton(_ node: VaultNode, depth: Int) -> some View {
        Button {
            if node.isDirectory {
                withAnimation(.easeOut(duration: FlintMotion.base)) { toggle(node.url) }
            } else {
                onSelectNote?()
                vault.open(node)
            }
        } label: {
            HStack(spacing: FlintSpace.s2) {
                Group {
                    if node.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(FlintColor.textMuted)
                            .rotationEffect(.degrees(expanded.contains(node.url) ? 90 : 0))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 10)

                Image(systemName: node.isDirectory ? "folder" : "doc.text")
                    .foregroundStyle(FlintColor.textSecondary)
                    .frame(width: 20)

                Text(node.name)
                    .foregroundStyle(isSelected(node) ? FlintColor.textPrimary : FlintColor.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * FlintSpace.s4 + FlintSpace.s4)
            .padding(.trailing, FlintSpace.s4)
            .padding(.vertical, FlintSpace.s2)
            .contentShape(Rectangle())
            .background(rowBackground(node))
        }
        .buttonStyle(.flintRow(pressedFill: FlintColor.surfaceRaised))
    }

    private func toggle(_ url: URL) {
        if expanded.contains(url) { expanded.remove(url) } else { expanded.insert(url) }
    }

    private func isSelected(_ node: VaultNode) -> Bool {
        !node.isDirectory && node.id == vault.selection?.id
    }

    @ViewBuilder
    private func rowBackground(_ node: VaultNode) -> some View {
        if dropTarget == node.url {
            FlintColor.accent.opacity(0.15)         // drop here
        } else if isSelected(node) {
            ZStack(alignment: .leading) {
                FlintColor.surfaceRaised
                FlintColor.accent.frame(width: 2)   // "you are here" spark
            }
        } else {
            Color.clear
        }
    }
}

/// The detail pane hosts the editor's WKWebView (EditorHost). T3.1 loads a
/// placeholder runtime that proves the flint:// scheme + bridge round-trip;
/// CodeMirror and doc load/save arrive in T3.2. The nav bar shows the open
/// note's name, or the empty state when none is selected.
private struct NoteDetail: View {
    let vault: VaultStore

    var body: some View {
        Group {
            if let selection = vault.selection {
                EditorWebView(vault: vault, path: vault.selectedRelativePath)
                    .background(FlintColor.bg)
                    .navigationTitle(selection.name)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ZStack {
                    FlintColor.bg.ignoresSafeArea()
                    ContentUnavailableView("Select a note", systemImage: "doc.text")
                }
            }
        }
    }
}
