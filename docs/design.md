---
version: alpha
name: Flint
description: >-
  Warm, dark-first design system for a local-first note-taking app,
  derived from the app icon — a faceted flint stone throwing amber sparks
  on a warm near-black field. Two render engines (SwiftUI + CodeMirror in
  WKWebView) share one token source so the seam is invisible.

colors:
  # ── Primitive: Warm neutral ramp ──────────────────────────────────
  # R ≥ G ≥ B throughout — faint olive/khaki cast, never blue.
  # Steps marked ◆ are lifted directly from the app icon SVG.
  warm-0: "#FFFFFF"
  warm-50: "#FCFBF7"
  warm-100: "#F7F5F0"
  warm-150: "#E4E1D9"
  warm-200: "#C9C7C0"
  warm-300: "#A9A79F"
  warm-400: "#888780"           # ◆ icon edge
  warm-500: "#6B6A64"
  warm-600: "#5F5E5A"           # ◆ icon light facet
  warm-700: "#444441"           # ◆ icon stone
  warm-800: "#2C2C2A"           # ◆ icon dark facet
  warm-850: "#232220"
  warm-900: "#1A1917"           # ◆ icon field

  # ── Primitive: Spark accent (amber) ──────────────────────────────
  spark-300: "#FAC775"          # hover/bright (dark mode)
  spark-500: "#EF9F27"          # the spark — base accent
  spark-700: "#B5740C"          # pressed
  spark-800: "#9A6206"          # darkened for text on light bgs
  spark-selection: "rgba(239,159,39,0.22)"

  # ── Semantic: Dark mode (primary) ────────────────────────────────
  bg: "#1A1917"
  surface: "#232220"
  surface-raised: "#2C2C2A"
  border: "#444441"
  border-subtle: "#2C2C2A"
  text-primary: "#EDEBE6"
  text-secondary: "#A9A79F"
  text-muted: "#888780"
  accent: "#EF9F27"
  text-on-accent: "#1A1917"
  accent-text: "#EF9F27"
  accent-hover: "#FAC775"
  accent-pressed: "#B5740C"
  selection: "rgba(239,159,39,0.22)"
  cursor: "#EF9F27"
  paper-background: "#FCFBF7"
  paper-rule: "#E4E1D9"

  # ── Semantic: Light mode overrides ───────────────────────────────
  bg-light: "#F7F5F0"
  surface-light: "#FFFFFF"
  surface-raised-light: "#FCFBF7"
  border-light: "#E4E1D9"
  border-subtle-light: "#E4E1D9"
  text-primary-light: "#1A1917"
  text-secondary-light: "#6B6A64"
  text-muted-light: "#888780"
  accent-light: "#EF9F27"
  text-on-accent-light: "#1A1917"
  accent-text-light: "#9A6206"
  accent-hover-light: "#B5740C"
  accent-pressed-light: "#9A6206"
  selection-light: "rgba(239,159,39,0.22)"
  cursor-light: "#B5740C"
  paper-background-light: "#FCFBF7"
  paper-rule-light: "#E4E1D9"

typography:
  reading-h1:
    fontFamily: "ui-serif, 'New York', Charter, Georgia, serif"
    fontSize: 28px
    fontWeight: 700
    lineHeight: 1.3
  reading-h2:
    fontFamily: "ui-serif, 'New York', Charter, Georgia, serif"
    fontSize: 23px
    fontWeight: 700
    lineHeight: 1.35
  reading-h3:
    fontFamily: "ui-serif, 'New York', Charter, Georgia, serif"
    fontSize: 20px
    fontWeight: 600
    lineHeight: 1.4
  reading-base:
    fontFamily: "ui-serif, 'New York', Charter, Georgia, serif"
    fontSize: 18px
    fontWeight: 400
    lineHeight: 1.6
  reading-small:
    fontFamily: "ui-serif, 'New York', Charter, Georgia, serif"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.55
  ui-largeTitle:
    fontFamily: "ui-sans-serif, -apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 34px
    fontWeight: 700
    lineHeight: 1.2
  ui-title:
    fontFamily: "ui-sans-serif, -apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 22px
    fontWeight: 700
    lineHeight: 1.3
  ui-body:
    fontFamily: "ui-sans-serif, -apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 17px
    fontWeight: 400
    lineHeight: 1.5
  ui-secondary:
    fontFamily: "ui-sans-serif, -apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.5
  ui-caption:
    fontFamily: "ui-sans-serif, -apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.4
  code:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace"
    fontSize: 14.5px
    fontWeight: 400
    lineHeight: 1.5

rounded:
  none: 0px
  sm: 6px
  md: 10px
  lg: 16px
  xl: 22px

spacing:
  1: 4px
  2: 8px
  3: 12px
  4: 16px
  5: 24px
  6: 32px
  8: 48px
  10: 64px

components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.text-on-accent}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.md}"
    padding: "{spacing.4} {spacing.5}"
    height: 44px
  button-primary-hover:
    backgroundColor: "{colors.accent-hover}"
    textColor: "{colors.text-on-accent}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.md}"
    padding: "{spacing.4} {spacing.5}"
    height: 44px
  button-primary-pressed:
    backgroundColor: "{colors.accent-pressed}"
    textColor: "{colors.text-on-accent}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.md}"
    padding: "{spacing.4} {spacing.5}"
    height: 44px
  button-secondary:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.md}"
    padding: "{spacing.4} {spacing.5}"
    height: 44px
  button-secondary-hover:
    backgroundColor: "{colors.border}"
    textColor: "{colors.text-primary}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.md}"
    padding: "{spacing.4} {spacing.5}"
    height: 44px
  button-secondary-pressed:
    backgroundColor: "{colors.border}"
    textColor: "{colors.text-primary}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.md}"
    padding: "{spacing.4} {spacing.5}"
    height: 44px
  button-tertiary:
    backgroundColor: transparent
    textColor: "{colors.text-secondary}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.md}"
    padding: "{spacing.2}"
    size: 44px
  search-field:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.md}"
    padding: "{spacing.2} {spacing.3}"
    height: 36px
  tag-chip:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.accent-text}"
    typography: "{typography.ui-caption}"
    rounded: "{rounded.sm}"
    padding: "{spacing.1} {spacing.2}"
  tag-chip-active:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.accent-text}"
    typography: "{typography.ui-caption}"
    rounded: "{rounded.sm}"
    padding: "{spacing.1} {spacing.2}"
  sidebar-row:
    backgroundColor: transparent
    textColor: "{colors.text-primary}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.sm}"
    padding: "{spacing.2} {spacing.4}"
  sidebar-row-selected:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    typography: "{typography.ui-body}"
    rounded: "{rounded.sm}"
    padding: "{spacing.2} {spacing.4}"
  editor-surface:
    backgroundColor: "{colors.bg}"
    textColor: "{colors.text-primary}"
    typography: "{typography.reading-base}"
    rounded: 0px
    padding: "{spacing.5}"
    width: 68ch
  ink-canvas:
    backgroundColor: "{colors.paper-background}"
    textColor: "{colors.text-primary}"
    rounded: 0px
  ink-embed:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.md}"
    padding: "{spacing.3}"
---

# Flint Design System

## Overview

Flint is an open-source, local-first note-taking app for iOS and iPadOS that replaces Obsidian where it limits: quality ink (PencilKit) inside a connected canvas, with native agentic AI. The design system descends from a single image — the app icon: a warm dark field, a faceted stone, a few amber sparks. Read the icon literally; it tells you what Flint feels like.

The interface is a daily reading and writing tool, not a landing page. The chrome recedes; the user's text is the brightest, highest-contrast thing on screen. Warmth (R ≥ G ≥ B, never cold) is non-negotiable — it is what makes Flint not look like every other dev tool. The amber spark is rare: it marks moments of action and nothing else. Dark mode is primary; light mode is a faithful derivation.

Two render engines share one visual identity: SwiftUI chrome and CodeMirror in a WKWebView. The canonical token source is `docs/design/tokens/tokens.json`, which generates both `Tokens.swift` and `tokens.css`. This file (`design.md`) is a synthesis for coding agents; the `.html` twin is the human-readable mirror. Neither replaces `tokens.json` — they present it.

**North stars:** Obsidian, iA Writer, Things, Bear, Apple Notes.
**Anti-stars:** dashboard/SaaS chrome, gradient-heavy AI aesthetics, Awwwards splash pages.

## Colors

The palette is extracted directly from the app icon SVG. Five warm grays (`warm-900` through `warm-400`) form the neutral ramp, and two ambers (`spark-500`, `spark-300`) form the accent. Every neutral carries a warm cast — faint olive/khaki, never blue. No pure `#000` or `#FFF` in the system.

Dark mode is primary — the icon was born in the dark. Semantic tokens step through three surface planes: `bg` (deepest), `surface` (panels), `surface-raised` (cards and popovers). Light mode inverts onto the top of the ramp (`warm-100` → `warm-0` → `warm-50`). Both modes pass WCAG AA for all text pairs; proofs are maintained in `docs/design/COLOR.md`.

The amber accent (`spark-500`, `#EF9F27`) is gorgeous on dark backgrounds (8.2:1 on `bg`, AAA) but fails WCAG on white (2.2:1). This is a real decision (ADR-D02): amber stays as-is for fills, icons, and the cursor in both modes. For amber **text and links** in light mode, `accent-text` darkens to `spark-800` (`#9A6206`, 5.1:1, AA). This is the single place the palette intentionally diverges by mode.

The Markdown syntax palette for CodeMirror is deliberately restrained (iA Writer / Obsidian school): structure comes from weight and dimmed markup characters, not from a rainbow. Headings are bold `text-primary`; links and tags are `accent-text`; the markup characters (`#`, `*`, `-`, `[[`) dim to `text-muted`.

## Typography

Three native, zero-bundle typefaces — chosen so SwiftUI chrome and the CodeMirror webview render identical fonts with no licensing, no FOUT, and no payload.

**New York** (system editorial serif) for the editor body. It reads as a document, not an app form — calmer and more editorial, pairing with the warm palette. This is the most-stared-at surface in the app; a serif serves it better than a sans.

**SF Pro** (system sans) for UI chrome — labels, buttons, navigation. Controls feel native and respect Dynamic Type scaling.

**SF Mono** for code blocks, inline code, and fenced blocks in the editor.

The reading scale is generous: 18px base at 1.6 line-height for hours of writing. The column caps at `68ch` (`reading-measure`) — lines longer than ~70 characters hurt readability. The UI scale maps to iOS text styles (`.body`, `.largeTitle`, etc.) so chrome scales with the user's Dynamic Type setting. Never disable zoom in the webview. Weight and size carry hierarchy — not color; color hierarchy is reserved for the amber spark.

**Rules:** no fourth typeface. Italic means emphasis; bold means strong or heading — don't repurpose them decoratively.

## Layout

A 4pt spatial grid governs all spacing: `spacing-1` (4px) through `spacing-10` (64px). Density is comfortable — generous enough for a reading tool used for hours, tight enough that navigation doesn't waste space.

The editor content column centers at max `68ch` with `spacing-5`+ horizontal padding so text never kisses the edge. Sidebar rows use `spacing-2` vertical padding and `spacing-4` leading inset per depth level.

The navigation shell adapts by width class. **iPhone (compact):** a push drawer — the file tree shoves the note aside (no overlay), opened by a toolbar toggle or edge-swipe. **iPad (regular):** an overlay floats over a full-width note behind a light scrim (`black` @ ~12%), slides from the leading edge, and dismisses on scrim tap. The note never gets squeezed.

Elevation is structural, not theatrical. Three surface planes step through the warm ramp (`bg` → `surface` → `surface-raised`), separated by hairline borders. Shadows appear only for truly floating elements (popovers, sheets) and stay faint.

## Elevation & Depth

The icon shows depth through facets — planes of slightly different warm gray separated by a 2px edge, not a drop shadow. Flint mirrors that: hierarchy comes from surface color steps on the warm ramp plus hairline borders, never from heavy shadows.

**Level 0 (ground):** `bg` — the deepest surface, the app background.
**Level 1 (panel):** `surface` with a `border-subtle` hairline — the sidebar, secondary panels.
**Level 2 (raised):** `surface-raised` with a `border` hairline — cards, chips, code blocks, popovers.
**Popover/sheet:** `surface-raised` with `border` plus a faint shadow (`0 4px 16px rgba(0,0,0,0.28)`) — the only place a shadow appears.

This strategy keeps the visual weight low and the palette the source of depth, which is essential for a warm tool that avoids cold, corporate elevation. Always pair surfaces with their border token; never leave a raised surface floating without visual separation.

## Shapes

The icon is a rounded squircle holding a sharp-edged stone. Flint mirrors that split: **soft outside, crisp inside.**

Outer containers — cards, sheets, popovers, chips, buttons — use continuous (squircle) corners from the `rounded` scale. `sm` (6px) for inline elements like tag chips and sidebar row selections. `md` (10px) for buttons, search fields, and standard cards. `lg` (16px) and `xl` (22px) for sheets, modals, and the app-icon-scale squircle.

Content surfaces — the editor, the ink canvas — have `radius-none`. Roundness frames the work; it never softens the work itself. This is the clearest visual signal of the icon's philosophy: a smooth container holding a sharp, real thing.

On iOS, use SwiftUI's `.continuous` corner style for the squircle contour, not the default circular arc.

## Components

**Buttons.** Primary (the spark — max one per view): `accent` fill, `text-on-accent` label (dark text on amber, contrast-safe in both modes), `radius-md`, ≥44pt tall. Secondary: `surface-raised` fill, `text-primary`, `border` hairline, `radius-md`. Tertiary: icon-only, no fill, SF Symbol in `text-secondary`, ≥44×44pt tap target. All buttons get a press state: scale to **0.97** and/or one-step fill shift over `motion-fast` (120ms). Honor Reduce Motion — scale collapses to an instant fill change.

**Search.** Field: `surface-raised`, `radius-md`, `border-subtle`, leading `magnifyingglass` in `text-muted`, placeholder in `text-muted`. Result rows show the matched term in `accent-text` (colored text, not highlighted background — restraint). Empty/no-results: a quiet centered `text-secondary` line, no illustration.

**Tags.** Inline chips: `surface-raised` fill, `radius-sm`, label in `accent-text`, `ui-caption` type. Tags are navigational sparks, so amber is correct here. Active filter chip gets an `accent` 2px underline, not a full fill.

**Sidebar.** Rows at `spacing-2` vertical padding. Disclosure chevrons in `text-muted`. Selected row: `surface-raised` fill, `radius-sm`, label in `text-primary`, plus a 2px `accent` bar on the leading edge — the spark marking "you are here." Folder expand rotates the chevron and reveals children with a fade+slide (`motion-base`).

**Editor.** The core surface. `bg` background, `reading-base` serif, `text-primary` text, max width `68ch`, `spacing-5`+ padding. Caret: `cursor` (amber). Selection: `selection` (translucent amber). Markdown syntax: per the syntax palette — headings by weight, links/tags in `accent-text`, markup characters dimmed to `text-muted`, code on `surface-raised`. Content has `radius-none`.

**Ink canvas.** `paper-background` fill; rule lines/dots/grid in `paper-rule` (faint). Templates: blank, lined, grid, dotted — ruled at 32pt rhythm. Chrome is minimal: `surface` bar with `border` top hairline, back/done in `text-primary`. Haptic snapping to template grid/line via `UICanvasFeedbackGenerator` with Apple Pencil Pro — the one place iPad tactile exists.

**Ink embed.** `![[sketch.ink]]` renders as a CodeMirror widget: native-exported PNG in `surface-raised`, `border`, `radius-md`, modest max-height. A `pencil.tip` SF Symbol badge in `text-muted` signals "handwritten, tap to edit." Loading: placeholder box at final size (no layout shift) in `surface-raised`.

## Do's and Don'ts

**Do:**
- ✓ Use semantic token names in code (`FlintColor.bg`, `var(--flint-bg)`), never primitives or raw hex
- ✓ Keep the amber spark rare — one primary button per view, amber on the active element only
- ✓ Verify WCAG AA contrast for every new text/background pair; use `accent-text` (not `accent`) for amber text on light backgrounds
- ✓ Honor Reduce Motion and `prefers-reduced-motion` — all animations degrade to instant or cross-fade
- ✓ Use SF Symbols for standard affordances; map chrome to Dynamic Type text styles
- ✓ Test the SwiftUI ↔ CodeMirror seam: both sides must render identical colors, type, and spacing from the same tokens

**Don't:**
- ✗ Never use cold/blue-gray neutrals, pure `#000`, or pure `#FFF` — warmth is the identity
- ✗ Never introduce a fourth typeface — three is the system
- ✗ Never add decorative gradients, glows, hero imagery, or "delightful" motion — this is a reading tool, not a landing page
- ✗ Never create drop shadows for non-floating elements — depth comes from surface color steps and hairline borders
- ✗ Never apply rounded corners to the editor or ink canvas content — roundness frames containers, content stays crisp
- ✗ Never fire haptics per-keystroke or on scroll — haptics are the amber of touch, rare and semantic
