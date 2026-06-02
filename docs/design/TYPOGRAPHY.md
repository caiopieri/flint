# Flint — Typography

Three typefaces, all **native to Apple platforms and zero-bundle**. This is deliberate: it costs nothing to ship, and — crucially — it lets the SwiftUI chrome and the CodeMirror webview render the *same* fonts, keeping the seam invisible (see [PRINCIPLES.md §7](./PRINCIPLES.md), ADR-D03).

| Role | Family | SwiftUI | CSS |
|---|---|---|---|
| **Reading** (editor body) | **New York** (Apple's editorial serif) | `.system(design: .serif)` | `ui-serif, "New York", Charter, Georgia, serif` |
| **UI** (chrome, labels, buttons) | **SF Pro** (system) | default / `.system(...)` | `ui-sans-serif, -apple-system, system-ui, sans-serif` |
| **Code / Markdown source** | **SF Mono** | `.system(design: .monospaced)` | `ui-monospace, "SF Mono", Menlo, monospace` |

`ui-serif` resolves to New York on iOS/macOS, so the editor's serif matches the native serif for free — no webfont, no FOUT, no licensing.

## Why a serif for the editor

The body text is the most-stared-at surface in the app (Principle §1). A serif (New York) reads as a *document*, not an *app form* — calmer and more editorial, and it pairs with the warm palette. UI chrome stays on SF Pro so controls feel native. This split (serif content / sans chrome) is the iA Writer / editorial lineage.

## Reading scale (serif — the editor)

Generous size and line-height for long-form. Defined in `tokens.json` → `type.reading`.

| Token | Size | Line-height | Weight |
|---|---|---|---|
| `reading.h1` | 28 | 1.30 | bold |
| `reading.h2` | 23 | 1.35 | bold |
| `reading.h3` | 20 | 1.40 | semibold |
| `reading.base` | 18 | 1.60 | regular |
| `reading.small` | 15 | 1.55 | regular |

**Measure:** cap the editor text column at `68ch` (`--flint-reading-measure`). Lines longer than ~70 characters hurt readability; don't let the column run the full iPad width.

## UI scale (sans — native chrome)

These are the **default-Dynamic-Type** reference sizes. Native code should prefer iOS text styles (`.body`, `.headline`, `.largeTitle`, …) so everything scales with the user's setting; the numbers below are the baseline those styles resolve to.

| Token | Size | Weight | Maps to (iOS style) |
|---|---|---|---|
| `ui.largeTitle` | 34 | bold | `.largeTitle` |
| `ui.title` | 22 | bold | `.title2` |
| `ui.body` | 17 | regular | `.body` |
| `ui.secondary` | 15 | regular | `.subheadline` |
| `ui.caption` | 13 | regular | `.footnote` |

## Code

`type.code`: 14.5 / line-height 1.5, SF Mono. Used for inline code, fenced blocks, and (optionally) a future Markdown source-mode.

## Dynamic Type

- **Native UI must scale.** Use text styles, not fixed sizes, for chrome. Hit targets stay ≥ 44pt regardless (see [ACCESSIBILITY.md](./ACCESSIBILITY.md)).
- **The editor** should respect at least a user-set base reading size; the reading scale above is the default, not a ceiling. The CodeMirror side should expose the same base size so both engines scale together.
- Never disable text zoom in the webview.

## Rules

- Don't introduce a fourth family. Three is the system.
- Weight and size carry hierarchy — not color (color hierarchy is reserved for the amber spark, used rarely).
- Italic = emphasis; bold = strong/heading. Don't repurpose them decoratively.
