import SwiftUI

/// The app frame once a vault is open. Picks the right shell per width:
/// iPad/regular → side-by-side NavigationSplitView (hideable); iPhone/compact →
/// a push drawer (the tree shoves the note aside, Obsidian-style — not overlay).
/// Spec: docs/design/COMPONENTS.md → "Navigation shell · T1".
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarContent(vault: vault, chooseVault: chooseVault)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            NavigationStack {
                NoteDetail(vault: vault)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Toggle Sidebar", systemImage: "sidebar.leading") {
                                withAnimation {
                                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                                }
                            }
                        }
                    }
            }
        }
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
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button("New note", systemImage: "square.and.pencil") {
                onSelectNote?()
                Task { await vault.createNote() }
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(FlintColor.textSecondary)
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

/// A flat List driven by an explicit expansion set, so the **whole row** is the
/// tap target (folders toggle, files open) — not just the label text.
private struct VaultTreeList: View {
    let vault: VaultStore
    var onSelectNote: (() -> Void)?
    @State private var expanded: Set<URL> = []

    var body: some View {
        List {
            ForEach(flattened(vault.tree?.children ?? [], depth: 0), id: \.node.id) { item in
                row(item.node, depth: item.depth)
                    .listRowBackground(rowBackground(item.node))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(FlintColor.surface)
    }

    private func flattened(_ nodes: [VaultNode], depth: Int) -> [(node: VaultNode, depth: Int)] {
        var rows: [(VaultNode, Int)] = []
        for node in nodes {
            rows.append((node, depth))
            if node.isDirectory, expanded.contains(node.url), let kids = node.children {
                rows.append(contentsOf: flattened(kids, depth: depth + 1))
            }
        }
        return rows
    }

    private func row(_ node: VaultNode, depth: Int) -> some View {
        Button {
            if node.isDirectory {
                withAnimation(.easeOut(duration: FlintMotion.fast)) { toggle(node.url) }
            } else {
                onSelectNote?()
                Task { await vault.open(node) }
            }
        } label: {
            HStack(spacing: FlintSpace.s2) {
                Group {
                    if node.isDirectory {
                        Image(systemName: expanded.contains(node.url) ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(FlintColor.textMuted)
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
            .padding(.leading, CGFloat(depth) * FlintSpace.s4)
            .padding(.vertical, FlintSpace.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ url: URL) {
        if expanded.contains(url) { expanded.remove(url) } else { expanded.insert(url) }
    }

    private func isSelected(_ node: VaultNode) -> Bool {
        !node.isDirectory && node.id == vault.selection?.id
    }

    @ViewBuilder
    private func rowBackground(_ node: VaultNode) -> some View {
        if isSelected(node) {
            ZStack(alignment: .leading) {
                FlintColor.surfaceRaised
                FlintColor.accent.frame(width: 2)   // "you are here" spark
            }
        } else {
            Color.clear
        }
    }
}

/// T1 shows the raw `.md` text (read-only). The CodeMirror editor replaces this
/// in T3; for now this proves coordinated reads work end-to-end. The nav bar
/// shows the open note's name, or nothing when none is selected.
private struct NoteDetail: View {
    let vault: VaultStore

    var body: some View {
        Group {
            if let text = vault.noteText, let selection = vault.selection {
                ScrollView {
                    VStack(alignment: .leading, spacing: FlintSpace.s3) {
                        Text("Read-only preview — the editor arrives in T3.")
                            .font(.caption)
                            .foregroundStyle(FlintColor.textMuted)
                        Text(text)
                            .font(FlintFont.readingBase)
                            .foregroundStyle(FlintColor.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(FlintSpace.s5)
                }
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
