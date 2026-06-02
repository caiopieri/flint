import SwiftUI
import UniformTypeIdentifiers

/// Root shell. Switches between the empty state (no vault) and the vault
/// navigator, and owns the single folder picker (.fileImporter, ADR-011).
struct ContentView: View {
    @State private var vault = VaultStore()
    @State private var isPickingFolder = false

    var body: some View {
        Group {
            if vault.hasVault {
                VaultNavigator(vault: vault, chooseVault: { isPickingFolder = true })
            } else {
                VaultEmptyState { isPickingFolder = true }
            }
        }
        // Layer-2 haptics (iPhone only; no-op on iPad), per INTERACTION.md allowlist:
        // a light tick when a note is opened, an alert tap when an error surfaces.
        .flintHaptic(.selection, trigger: vault.selection) { $0 != nil }
        .flintHaptic(.error, trigger: vault.errorMessage) { $0 != nil }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): vault.openVault(at: url)
            case .failure(let error): vault.errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Vault",
            isPresented: Binding(
                get: { vault.errorMessage != nil },
                set: { if !$0 { vault.errorMessage = nil } }
            ),
            presenting: vault.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

#Preview {
    ContentView()
}
