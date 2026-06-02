# Flint — Interaction & Haptics

The "tactile" feeling of a good button is **two layers** working together:

1. **Visual press state** — the control reacts to touch (a slight scale-down, a fill shift). Works on *every* device and inside the webview.
2. **Haptic feedback** — the Taptic Engine taps your finger. Hardware-limited (see below).

The brain reads the combination as "tactile." Haptic without a visual reaction is confusing; a visual reaction without haptic is what plain web has — it feels inert on touch. So we always ship **layer 1 everywhere** and add **layer 2 where the hardware allows**.

The governing principle: **haptics is the amber of touch.** Like the spark (§3), it marks *moments that matter* and nothing else; like motion (§9), it is functional or absent. A reading/writing tool used for hours punishes haptic overuse — it becomes noise, then fatigue, then the user disables it.

---

## The hardware reality (read this before designing any haptic)

These limitations are not edge cases — they decide the whole approach. **Flint runs on iPhone *and* iPad, and they do not feel the same.**

| Surface | Taptic hardware | What works |
|---|---|---|
| **iPhone** (7+) | Full Taptic Engine | All UI haptics (`.selection`, `.impact`, `.success/.warning/.error`). |
| **iPad** (every model) | **None** | UI haptics **silently do nothing** — the call succeeds, the user feels nothing. |
| **iPad + Apple Pencil Pro** | Pencil haptics (2024+) | `UICanvasFeedbackGenerator` (iOS 17.5+) — alignment/snap taps on a canvas. Pencil-Pro squeeze handled by PencilKit. |
| **iPad + Magic Keyboard (M4)** | Trackpad haptics | System-driven; not a button channel we drive directly. |
| **Editor (CodeMirror in WKWebView)** | n/a | JS **cannot** fire the Taptic Engine. A web-side tap must cross the native bridge (see below). |

**Consequences, made into rules:**

- **Haptics is an enhancement, never load-bearing.** No action may rely on haptics as its only feedback — half the audience (iPad) feels nothing. Every haptic is paired with a visual change that already works everywhere (layer 1).
- **The iPad's only real tactile channel is Ink + Apple Pencil.** Don't fake iPad button haptics; invest the tactile budget where it physically exists — snapping on the canvas.
- **Respect the system.** `UIFeedbackGenerator` / `.sensoryFeedback` already honor the user's **System Haptics** setting and Low Power Mode automatically. On top of that, provide an **in-app toggle** (HIG). Note: haptics are governed by *System Haptics*, **not** by Reduce Motion — don't gate them on the wrong setting.
- **Capability, not device model.** Detect the ability to play feedback; never branch on `UIDevice` model strings.

---

## Layer 1 — press states (everywhere, including iPad & webview)

The always-on baseline. Calm, matching the "tool disappears" restraint (§1) — no bounce, no spring overshoot.

- **Tap-down:** scale to **0.97** and/or shift fill one ramp step (e.g. `surface-raised` → its pressed tint). Duration `motion.fast` (120ms), easing `standard`.
- **Tap-up / release:** return to rest over `motion.fast`.
- **Disabled:** no press reaction; reduced text/fill contrast.
- Honor Reduce Motion: the scale collapses to an instant fill change (no animated transform).

These are the same values both engines read from tokens, so a CodeMirror toolbar button and a SwiftUI button press identically (§7).

---

## Layer 2 — the haptic map (where hardware allows)

Restraint is the whole point. The default is **no haptic**; the table is the *complete* allowlist, not a menu of suggestions.

| Surface / action | Haptic | Platform | Why |
|---|---|---|---|
| **Primary button** (the spark — max 1 per view) | `.impact(.medium)` on commit | iPhone | Reinforces "this matters." Rare by construction, so it never fatigues. |
| **Select / open a note**, change tab | `.selection` (light tick) on *commit only* | iPhone | Marks "you are here." **Never** fire during scroll or per-row as the finger drags. |
| **Toggle tag filter chip** | `.selection` | iPhone | Discrete state change. |
| **Toggle / switch, pull-to-refresh, reorder drag** | **none — native already provides it** | iPhone | Don't double up on what the system control emits for free. |
| **Local autosave** | **none** | — | Already silent by design (no blocking spinner). A tap per save would be torture. |
| **Real error** (vault import fails, sync conflict surfaced) | `.error` | iPhone | Rare and meaningful — earns the physical alert. |
| **Ink — snap to template grid/line or ruler** | `UICanvasFeedbackGenerator` | **iPad + Pencil Pro** | The one place iPad tactile exists. The defining Ink feel. |
| **Ink — Pencil Pro squeeze (tool palette)** | native gesture haptic | iPad + Pencil Pro | Free via PencilKit; don't re-implement. |

If a new surface isn't in this table, its default is **no haptic** — add a row here (and justify it) rather than sprinkling feedback ad hoc.

---

## Crossing the bridge (editor / webview UI)

Buttons rendered by CodeMirror can't reach the Taptic Engine from JS. When a web-side control genuinely warrants a haptic, it requests one through the typed native bridge — e.g. a coarse `Flint.haptic('selection' | 'impact' | 'success' | 'warning' | 'error')` call that the native side maps to `.sensoryFeedback` / `UIFeedbackGenerator`.

This obeys the `AGENTS.md` boundary rule: the bridge is **coarse and async**. Discrete, user-initiated taps are fine; **per-keystroke haptics are forbidden** (chatty bridge traffic). Typing feedback, if ever wanted, lives entirely on the native keyboard/input side — never as a bridge round-trip per character.

---

## Implementation notes (for the dev agent)

Design-level guidance, not wiring — same handoff stance as the rest of `docs/design/`.

- Prefer SwiftUI **`.sensoryFeedback(_:trigger:)`** for native controls; drop to `UIFeedbackGenerator` where you need `prepare()` to cut latency before a known imminent tap.
- For Ink snapping, use **`UICanvasFeedbackGenerator`** tied to the snap/alignment event — not a generic impact.
- Persist the in-app **Haptics on/off** toggle in app settings; gate all custom haptics on it (the system setting is honored automatically, but an app-level off-switch is expected for a focus tool).
- There is **no haptic token** in `tokens.json` — haptics are semantic API calls, not visual values. Keep them in code keyed to the events in the table above, not to colors.

## Checklist for any new interactive surface

- [ ] Has a **visual** press state (layer 1) that works on iPad and in the webview
- [ ] Any haptic is in the allowlist table above (or the table was updated + justified)
- [ ] No action depends on haptics as its *only* feedback
- [ ] No haptic on scroll, drag-over, or autosave
- [ ] Web-side haptics go through the bridge, never per-keystroke
- [ ] Gated on the in-app Haptics toggle; relies on the OS for System-Haptics/Low-Power handling
