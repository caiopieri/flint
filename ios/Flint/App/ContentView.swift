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
