import SwiftUI

/// The app frame once a vault is open. iPhone collapses this to a stack; iPad
/// shows sidebar + detail. Spec: docs/design/COMPONENTS.md → "Navigation shell · T1".
struct VaultNavigator: View {
    let vault: VaultStore
    var chooseVault: () -> Void

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle(vault.tree?.name ?? "Vault")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New note", systemImage: "square.and.pencil") {
                            Task { await vault.createNote() }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
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
        } detail: {
            NoteDetail(vault: vault)
        }
    }

    private var isEmptyVault: Bool { vault.tree?.children?.isEmpty ?? true }

    @ViewBuilder
    private var sidebar: some View {
        if isEmptyVault {
            ZStack {
                FlintColor.surface.ignoresSafeArea()
                ContentUnavailableView {
                    Label("No notes yet", systemImage: "doc.text")
                } description: {
                    Text("This folder has no Markdown notes.")
                } actions: {
                    Button("New note") { Task { await vault.createNote() } }
                        .buttonStyle(.flintPrimary)
                        .frame(maxWidth: 240)
                }
            }
        } else {
            List {
                if let children = vault.tree?.children {
                    OutlineGroup(children, children: \.children) { node in
                        VaultRow(node: node, isSelected: node.id == vault.selection?.id) {
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
            }
        }
    }
}
