# Flint — Color

All values are defined once in [`tokens/tokens.json`](./tokens/tokens.json) and generated into `Tokens.swift` / `tokens.css`. This doc explains the *why* and records the contrast proofs. Reference **semantic** tokens in code (`FlintColor.bg`, `var(--flint-bg)`), never primitives or raw hex.

## The source

Five colors come straight off the [icon](../../assets/brand/flint-icon.svg): the field `#1A1917`, the dark facet `#2C2C2A`, the stone `#444441`, the light facet `#5F5E5A`, the edge `#888780`, plus the sparks `#EF9F27` / `#FAC775`. The system is those, extended into a complete ramp.

## Warm neutral ramp (primitive)

A single warm-gray ramp, `R ≥ G ≥ B` throughout — a faint olive/khaki cast, never blue. Icon-derived steps marked ◆.

| Token | Hex | Note |
|---|---|---|
| `warm.0` | `#FFFFFF` | pure white, used sparingly |
| `warm.50` | `#FCFBF7` | |
| `warm.100` | `#F7F5F0` | light paper |
| `warm.150` | `#E4E1D9` | |
| `warm.200` | `#C9C7C0` | |
| `warm.300` | `#A9A79F` | |
| `warm.400` | `#888780` | ◆ icon edge |
| `warm.500` | `#6B6A64` | |
| `warm.600` | `#5F5E5A` | ◆ icon light facet |
| `warm.700` | `#444441` | ◆ icon stone |
| `warm.800` | `#2C2C2A` | ◆ icon dark facet |
| `warm.850` | `#232220` | |
| `warm.900` | `#1A1917` | ◆ icon field |

## Spark accent (primitive)

| Token | Hex | Use |
|---|---|---|
| `spark.300` | `#FAC775` | hover/bright (dark mode) |
| `spark.500` | `#EF9F27` | the spark — base accent |
| `spark.700` | `#B5740C` | pressed |
| `spark.800` | `#9A6206` | **accent text on light backgrounds** (see caveat) |

## Semantic tokens (what code uses)

Dark is primary; light is derived.

| Token | Dark | Light | Role |
|---|---|---|---|
| `bg` | `warm.900` | `warm.100` | app background |
| `surface` | `warm.850` | `warm.0` | panels, sidebar |
| `surface-raised` | `warm.800` | `warm.50` | cards, popovers |
| `border` | `warm.700` | `warm.150` | hairline dividers |
| `border-subtle` | `warm.800` | `warm.150` | faint separation |
| `text-primary` | `#EDEBE6` | `warm.900` | body text (off-white in dark, not pure) |
| `text-secondary` | `warm.300` | `warm.500` | labels, metadata |
| `text-muted` | `warm.400` | `warm.400` | de-emphasized, markdown syntax chars |
| `accent` | `spark.500` | `spark.500` | fills, icon accents, cursor, the one CTA |
| `accent-text` | `spark.500` | `spark.800` | amber **text/links** (see caveat) |
| `accent-hover` | `spark.300` | `spark.700` | hover |
| `accent-pressed` | `spark.700` | `spark.800` | pressed |
| `selection` | `rgba(239,159,39,.22)` | same | text selection / active range |
| `cursor` | `spark.500` | `spark.700` | the text caret — the literal spark |

### ⚠️ The amber-on-light caveat (a real decision — see ADR-D02)

The icon's amber (`#EF9F27`) is gorgeous on dark but **fails WCAG on white (~2.2:1)**. So:
- Amber stays as-is for **fills, icons, the cursor** in both modes (non-text, contrast rules differ).
- For **amber text/links in light mode**, `accent-text` darkens to `spark.800` (`#9A6206`). This is the single place the palette intentionally diverges by mode.

## Markdown syntax palette (CodeMirror)

Restrained on purpose (iA/Obsidian school): structure comes from **weight and the dimmed markup characters**, not from a rainbow. Generated as aliases onto the semantic tokens.

| Element | Token alias → | Treatment |
|---|---|---|
| Heading | `text-primary` | bold |
| Strong | `text-primary` | bold |
| Emphasis | `text-primary` | italic |
| Link / URL | `accent-text` | amber |
| Tag (`#tag`) | `accent-text` | amber |
| Inline code / fence | `text-primary` on `surface-raised` | mono |
| Blockquote | `text-secondary` | — |
| **Markup chars** (`#`, `*`, `-`, `[[`) | `text-muted` | **dimmed** — the key move |

## Ink paper

| Token | Dark | Light |
|---|---|---|
| `paper-background` | `warm.900` | `warm.50` |
| `paper-rule` (lines/dots/grid) | `warm.800` | `warm.150` |

Rule lines are deliberately faint — visible enough to guide, quiet enough to ignore. Templates: blank, lined, grid, dotted (see [COMPONENTS.md](./COMPONENTS.md)).

## Contrast proofs (WCAG 2.1)

Computed against the relevant background. AA = 4.5:1 (normal text), 3:1 (large/UI).

| Pair | Ratio | Verdict |
|---|---|---|
| `text-primary` `#EDEBE6` on `bg` dark | ~14.6:1 | AAA |
| `text-secondary` `#A9A79F` on `bg` dark | ~7.0:1 | AAA |
| `text-muted` `#888780` on `bg` dark | ~4.9:1 | AA |
| `accent` `#EF9F27` on `bg` dark | ~8.2:1 | AAA — amber works as dark-mode text |
| `text-primary` `#1A1917` on `bg` light | ~15.1:1 | AAA |
| `text-secondary` `#6B6A64` on `bg` light | ~5.3:1 | AA |
| `accent` `#EF9F27` on white | ~2.2:1 | ✗ fails → use `spark.800` for text |
| `accent-text` `#9A6206` on `bg` light | ~5.1:1 | AA ✓ |

Re-verify any pair you introduce; don't assume.
