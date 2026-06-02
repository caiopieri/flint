import SwiftUI

/// Phase 1a empty state — no vault chosen yet.
/// Spec: docs/design/COMPONENTS.md → "Navigation shell · T1" (Empty state) + Buttons.
/// The real navigator (T1) and CodeMirror editor (T3) replace this. Every value
/// references a design token (FlintColor/FlintSpace/FlintFont/FlintRadius) — never raw hex.
struct ContentView: View {
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
                // T1 wires this to .fileImporter + a security-scoped bookmark (ADR-011).
                Button {
                    // TODO(T1): present the folder picker, persist the bookmark.
                } label: {
                    Text("Choose vault folder")
                        .font(.headline)
                        .foregroundStyle(FlintColor.textOnAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            FlintColor.accent,
                            in: RoundedRectangle(cornerRadius: FlintRadius.md, style: .continuous)
                        )
                }
                .frame(maxWidth: 300)
            }
            .padding(FlintSpace.s6)
        }
    }
}

#Preview {
    ContentView()
}
