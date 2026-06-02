import SwiftUI

/// Phase 1a empty state — no vault chosen yet.
/// Spec: docs/design/COMPONENTS.md → "Navigation shell · T1" (Empty state) + Buttons.
/// Every value references a design token (FlintColor/FlintSpace/FlintFont/FlintRadius) — never raw hex.
struct VaultEmptyState: View {
    /// Triggers the folder picker owned by the root view.
    var chooseVault: () -> Void

    var body: some View {
        ZStack {
            FlintColor.bg.ignoresSafeArea()

            VStack(spacing: FlintSpace.s5) {
                // Brand mark stand-in. The faceted flint mark
                // (assets/brand/flint-icon.svg) is wired into the asset catalog
                // later (docs/design/ICONOGRAPHY.md → "App icon" is implementation).
                // SF Symbol keeps the layout and warm/amber tone correct for now.
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(FlintColor.accent)

                VStack(spacing: FlintSpace.s2) {
                    Text("Flint")
                        .font(FlintFont.readingH1)
                        .foregroundStyle(FlintColor.textPrimary)
                    Text("Choose a folder of Markdown files to open it as your vault.")
                        .font(FlintFont.readingSmall)
                        .foregroundStyle(FlintColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }

                // Primary button — the one amber spark on screen (§3).
                Button("Choose vault folder", action: chooseVault)
                    .buttonStyle(.flintPrimary)
                    .frame(maxWidth: 300)
            }
            .padding(FlintSpace.s6)
        }
    }
}

#Preview {
    VaultEmptyState(chooseVault: {})
}
