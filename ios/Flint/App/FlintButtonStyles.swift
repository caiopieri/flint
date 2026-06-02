import SwiftUI

/// The in-app "Haptics" toggle (HIG — expected on a focus tool). System Haptics
/// and Low Power Mode are honored automatically by the OS; this is the extra
/// app-level off-switch. No UI yet (a settings screen arrives later) — default on.
/// Spec: docs/design/INTERACTION.md.
enum FlintHaptics {
    static let enabledKey = "flint.haptics.enabled"
}

/// Layer-1 press visuals (INTERACTION.md): a calm scale-down over motion.fast,
/// collapsing to an instant change under Reduce Motion. Lives in a `View` so it
/// can read the environment and the haptics toggle — a `ButtonStyle` can't.
/// Optionally fires the primary "spark" impact on commit (release).
private struct PressableSurface<Content: View>: View {
    let isPressed: Bool
    var scale: CGFloat = 0.97
    var impactOnCommit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(FlintHaptics.enabledKey) private var hapticsEnabled = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .scaleEffect(reduceMotion ? 1 : (isPressed ? scale : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: FlintMotion.fast), value: isPressed)
            .sensoryFeedback(trigger: isPressed) { wasPressed, nowPressed in
                // Commit = the press is released. The spark earns one medium tap —
                // iPhone only (a silent no-op on iPad), gated by the in-app toggle.
                (impactOnCommit && hapticsEnabled && wasPressed && !nowPressed)
                    ? .impact(weight: .medium) : nil
            }
    }
}

/// The primary ("spark") button — amber fill, dark `text-on-accent` label,
/// continuous radius, ≥44pt. One per view max (§3). Press: fill shifts to
/// `accentPressed` + a 0.97 scale; commit fires `.impact(.medium)` on iPhone.
/// Spec: docs/design/COMPONENTS.md → Buttons; docs/design/INTERACTION.md.
struct FlintPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableSurface(isPressed: configuration.isPressed, impactOnCommit: true) {
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
}

/// The layer-1 press state for tertiary / icon / row buttons (no haptic — those
/// are reserved for the allowlist in INTERACTION.md). Icon buttons dim + scale;
/// rows shift their fill one step (`pressedFill`) without scaling.
struct FlintPressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var pressedFill: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        PressableSurface(isPressed: configuration.isPressed, scale: scale) {
            configuration.label
                .background(configuration.isPressed ? (pressedFill ?? Color.clear) : Color.clear)
                .opacity(configuration.isPressed && pressedFill == nil ? 0.72 : 1)
        }
    }
}

extension ButtonStyle where Self == FlintPrimaryButtonStyle {
    static var flintPrimary: FlintPrimaryButtonStyle { FlintPrimaryButtonStyle() }
}

extension ButtonStyle where Self == FlintPressableButtonStyle {
    /// Tertiary / icon button: dim + scale on press.
    static var flintPressable: FlintPressableButtonStyle { FlintPressableButtonStyle() }
    /// Full-width row: shift fill one step on press, no scale.
    static func flintRow(pressedFill: Color) -> FlintPressableButtonStyle {
        FlintPressableButtonStyle(scale: 1, pressedFill: pressedFill)
    }
}

extension View {
    /// Fire a layer-2 haptic when `trigger` changes to a value matching `when`,
    /// gated by the in-app Haptics toggle. iPad has no Taptic Engine, so this is
    /// a silent no-op there; the OS handles System-Haptics / Low-Power. Only use
    /// for actions on the INTERACTION.md allowlist. (Spec: docs/design/INTERACTION.md.)
    func flintHaptic<T: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: T,
        when: @escaping (T) -> Bool = { _ in true }
    ) -> some View {
        modifier(FlintHapticModifier(feedback: feedback, trigger: trigger, when: when))
    }
}

private struct FlintHapticModifier<T: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: T
    let when: (T) -> Bool
    @AppStorage(FlintHaptics.enabledKey) private var enabled = true

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { _, newValue in
            (enabled && when(newValue)) ? feedback : nil
        }
    }
}
