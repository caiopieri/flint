import SwiftUI
import UIKit

/// Full-screen startup state. It stays visible for the real vault load and a
/// short minimum interval, avoiding a white flash on fast launches.
struct FlintLaunchScreen: View {
    let hasVault: Bool

    var body: some View {
        ZStack {
            FlintColor.bg.ignoresSafeArea()

            VStack(spacing: FlintSpace.s5) {
                brandMark

                Text("Flint")
                    .font(FlintFont.readingH1)
                    .foregroundStyle(FlintColor.textPrimary)

                VStack(spacing: FlintSpace.s2) {
                    Text(hasVault ? "Opening your vault…" : "Loading Flint…")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(FlintColor.textSecondary)

                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(FlintColor.accent)
                        .frame(maxWidth: 320)
                }
            }
            .padding(FlintSpace.s6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasVault ? "Opening your vault" : "Loading Flint")
    }

    @ViewBuilder
    private var brandMark: some View {
        if let image = UIImage(named: "AppIcon") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(FlintColor.accent)
        }
    }
}

#Preview {
    FlintLaunchScreen(hasVault: true)
}
