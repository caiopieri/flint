import SwiftUI

/// The app frame once a vault is open. Picks the right shell per width:
/// iPad/regular → side-by-side NavigationSplitView; iPhone/compact → a push
/// drawer (the sidebar shoves the note aside, Obsidian-style — not an overlay).
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
            SidebarContent(vault: vault, chooseVault: chooseVault)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            NoteDetail(vault: vault)
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
                    .background(FlintColor.surface)
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
                    // Tap/drag the pushed-aside note to dismiss the drawer
                    // (no dimming — the sidebar pushes, it doesn't overlay).
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
                // Edge-swipe from the leading edge to open.
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

/// The vault name (tap to switch vault) + a new-note button, over the file tree.
private struct SidebarContent: View {
    let vault: VaultStore
    var chooseVault: () -> Void
    /// Lets the compact drawer close itself when a note is opened/created.
    var onSelectNote: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            FlintColor.border.frame(height: 1)
            tree
        }
        .background(FlintColor.surface)
    }

    private var header: some View {
        HStack(spacing: FlintSpace.s2) {
            Menu {
                Button("Open another vault…", systemImage: "folder", action: chooseVault)
                // TODO: recent vaults + create vault live here.
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

    @ViewBuilder
    private var tree: some View {
        if vault.tree?.children?.isEmpty ?? true {
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
