import SwiftUI
import UniformTypeIdentifiers

/// Root shell. Switches between the empty state (no vault) and the vault
/// navigator, and owns the single folder picker (.fileImporter, ADR-011).
struct ContentView: View {
    @State private var vault = VaultStore()
    @State private var modelStore = ModelStore()
    @State private var isPickingFolder = false
    @State private var showLaunchScreen = true
    @AppStorage("flint.appearance") private var appearance = "system"

    var body: some View {
        ZStack {
            Group {
                if vault.hasVault {
                    VaultNavigator(vault: vault, modelStore: modelStore, chooseVault: { isPickingFolder = true })
                } else {
                    VaultEmptyState { isPickingFolder = true }
                }
            }

            if showLaunchScreen {
                FlintLaunchScreen(hasVault: vault.hasVault)
                    .transition(.opacity)
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
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            while vault.isLoadingTree {
                try? await Task.sleep(for: .milliseconds(50))
            }
            showLaunchScreen = false
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

#Preview {
    ContentView()
}
