import SwiftUI

/// The app frame once a vault is open. Picks the right shell per width:
/// iPad/regular → a real side-by-side NavigationSplitView; iPhone/compact → a
/// slide-over drawer (Obsidian-style), since a fixed sidebar doesn't fit a phone.
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

    var body: some View {
        NavigationSplitView {
            VaultTree(vault: vault)
                .navigationTitle(vault.tree?.name ?? "Vault")
                .toolbar { vaultToolbar(vault: vault, chooseVault: chooseVault) }
        } detail: {
            NoteDetail(vault: vault)
        }
    }
}

// MARK: - iPhone / compact width — slide-over drawer

private struct CompactNavigator: View {
    let vault: VaultStore
    var chooseVault: () -> Void

    @State private var isDrawerOpen = false
    private let drawerWidth: CGFloat = 320

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                NoteDetail(vault: vault)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isDrawerOpen {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { setDrawer(false) }
                        .transition(.opacity)
                }

                VaultTree(vault: vault, onSelectNote: { setDrawer(false) })
                    .frame(width: drawerWidth, alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .background(FlintColor.surface)
                    .overlay(alignment: .trailing) { FlintColor.border.frame(width: 1) }
                    .offset(x: isDrawerOpen ? 0 : -(drawerWidth + 1))
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { if $0.translation.width < -40 { setDrawer(false) } }
                    )
            }
            // Thin leading strip to swipe the drawer open.
            .overlay(alignment: .leading) {
                if !isDrawerOpen {
                    Color.clear
                        .frame(width: 16)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { if $0.translation.width > 40 { setDrawer(true) } }
                        )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Files", systemImage: "sidebar.leading") { setDrawer(!isDrawerOpen) }
                }
                vaultToolbar(vault: vault, chooseVault: chooseVault)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { if vault.selection == nil { isDrawerOpen = true } }
    }

    private func setDrawer(_ open: Bool) {
        withAnimation(.easeOut(duration: FlintMotion.base)) { isDrawerOpen = open }
    }
}

// MARK: - Shared toolbar

@ToolbarContentBuilder
private func vaultToolbar(vault: VaultStore, chooseVault: @escaping () -> Void) -> some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
        Button("New note", systemImage: "square.and.pencil") {
            Task { await vault.createNote() }
        }
    }
    ToolbarItem(placement: .primaryAction) {
        Menu {
            Button("Change vault folder…", systemImage: "folder", action: chooseVault)
            Button("Reload", systemImage: "arrow.clockwise") {
                Task { await vault.reload() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

// MARK: - The tree (shared by both shells)

private struct VaultTree: View {
    let vault: VaultStore
    /// Called after a note is opened, so the compact drawer can close itself.
    var onSelectNote: (() -> Void)? = nil

    private var isEmpty: Bool { vault.tree?.children?.isEmpty ?? true }

    var body: some View {
        if isEmpty {
            ZStack {
                FlintColor.surface.ignoresSafeArea()
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
            }
        } else {
            List {
                if let children = vault.tree?.children {
                    OutlineGroup(children, children: \.children) { node in
                        VaultRow(node: node, isSelected: node.id == vault.selection?.id) {
                            onSelectNote?()
                            Task { await vault.open(node) }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(FlintColor.surface)
        }
    }
}

/// One row in the folder/note tree. Folders just expand; tapping a note opens it.
/// Selected note gets a surface-raised fill + a 2pt amber leading bar (§3).
private struct VaultRow: View {
    let node: VaultNode
    let isSelected: Bool
    var open: () -> Void

    var body: some View {
        if node.isDirectory {
            Label(node.name, systemImage: "folder")
                .foregroundStyle(FlintColor.textSecondary)
        } else {
            Button(action: open) {
                Label(node.name, systemImage: "doc.text")
                    .foregroundStyle(isSelected ? FlintColor.textPrimary : FlintColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, FlintSpace.s1)
            }
            .buttonStyle(.plain)
            .listRowBackground(
                ZStack(alignment: .leading) {
                    if isSelected {
                        FlintColor.surfaceRaised
                        FlintColor.accent.frame(width: 2)   // "you are here" spark
                    }
                }
            )
        }
    }
}

/// T1 shows the raw `.md` text (read-only). The CodeMirror editor replaces this
/// in T3; for now this proves coordinated reads work end-to-end.
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
                .navigationTitle(vault.tree?.name ?? "Vault")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
