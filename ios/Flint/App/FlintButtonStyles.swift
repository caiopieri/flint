import SwiftUI

/// The primary ("spark") button — amber fill, dark `text-on-accent` label,
/// continuous radius, ≥44pt. One per view max (§3). Spec: docs/design/COMPONENTS.md → Buttons.
struct FlintPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(FlintColor.textOnAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, FlintSpace.s5)
            .background(
                configuration.isPressed ? FlintColor.accentPressed : FlintColor.accent,
                in: RoundedRectangle(cornerRadius: FlintRadius.md, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: FlintRadius.md, style: .continuous))
    }
}

extension ButtonStyle where Self == FlintPrimaryButtonStyle {
    static var flintPrimary: FlintPrimaryButtonStyle { FlintPrimaryButtonStyle() }
}
