# Flint — Iconography & Brand Mark

## The mark

The Flint mark is a **faceted flint stone throwing a few amber sparks**, on a warm near-black field. Master: [`../../assets/brand/flint-icon.svg`](../../assets/brand/flint-icon.svg). It is not decoration — it is the design system's source (warm neutrals + rare spark + faceted planes). Treat it as canonical; the palette in [COLOR.md](./COLOR.md) must always agree with it.

**Construction (from the SVG):**
- Field: rounded square (`#1A1917`), `rx ≈ 22.5%` — the iOS app-icon squircle.
- Stone: a single faceted polygon (`#444441`) with a light facet (`#5F5E5A`), a dark facet (`#2C2C2A`), and a 2px edge (`#888780`).
- Sparks: three thin amber strokes (`#EF9F27`) + three dots, one lighter (`#FAC775`) at reduced opacity. **Few and small** — the whole "spark is rare" principle, drawn.

**Do not:** recolor the stone outside the warm ramp, add a gradient background, multiply the sparks into a shower, or place the mark on a cold/blue field.

## App icon

- Ship from the SVG master at the required iOS sizes (generate a 1024² App Store asset + the catalog set).
- The icon is **dark by default** and intentionally has no light variant for the home screen (iOS renders app icons on the user's wallpaper, not a theme background). If a tinted/mono variant is later wanted for iOS theming, derive it from the same geometry — stone in mono, spark preserved.
- **Dev-agent note:** wiring the `.appiconset` / asset catalog is implementation; the master and color spec are provided here.

## In-app icons — SF Symbols first

Per Principle §8 (native by default):

- **Use SF Symbols** for all standard affordances (navigation, search `magnifyingglass`, tags `number`, folders `folder`, etc.). They scale with Dynamic Type, support hierarchical/multicolor rendering, and feel native for free.
- **Tint:** icons inherit `text-secondary` at rest, `text-primary` when active/pressed. The amber `accent` tint is reserved for the *one* active/primary affordance in a view (§3) — e.g., the current tool in the Ink picker.
- **Custom SVG only where SF Symbols genuinely fall short** — e.g. an Ink-specific tool with no system equivalent. Custom glyphs must match SF Symbols' weight and optical size so they sit in a row without looking foreign. Keep them monoline and warm-neutral.
- The "handwritten embed" badge uses `pencil.tip` in `text-muted` (see [COMPONENTS.md](./COMPONENTS.md) → Ink embed).

## Wordmark

When the name is set in type, use the **UI sans (SF Pro)**, not the serif — the serif is for reading content, the brand is chrome. No custom letterforms in Phase 1.
