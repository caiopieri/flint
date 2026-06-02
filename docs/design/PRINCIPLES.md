# Flint — Design Principles

The design philosophy. If a design choice conflicts with these, stop and flag it — same status as the invariants in `AGENTS.md`.

The whole system descends from one image: the [app icon](../../assets/brand/flint-icon.svg). A warm dark field, a faceted stone, a few sparks. Read it literally — it tells you what Flint feels like.

---

## 1. The tool disappears; the words don't.

Flint is a daily writing/reading tool, not a landing page. The interface a person stares at for hours must recede. Chrome is quiet, low-contrast, and out of the way; the user's text is the brightest, highest-contrast thing on screen.

- Maximize the content area. Minimize persistent chrome.
- No decorative gradients, glows, hero imagery, or "delightful" motion. Those belong to marketing sites — a separate concern (see §7).
- Measure success by *legibility over an hour*, not by a first-glance screenshot.

**North stars:** Obsidian, iA Writer, Things, Bear, Apple Notes.
**Anti-stars:** dashboard/SaaS slop, gradient-heavy AI aesthetics, Awwwards splash pages.

## 2. Warm, never cold.

Every neutral carries a warm cast (R ≥ G ≥ B), lifted straight from the icon. No cold/blue-gray "slate," no pure `#000`/`#FFF`. Warmth is the difference between "comfortable for hours" and "clinical." This is non-negotiable and it is what makes Flint not look like every other dev tool. See [COLOR.md](./COLOR.md).

## 3. The amber spark is rare.

Striking flint throws *a few* sparks — that's the brand. The amber accent (`#EF9F27`) marks **moments of action and only those**: the text cursor, the active selection, the focused link/tag, the single primary button. If amber is everywhere, nothing is the spark. When in doubt, use a neutral; reserve amber for the one thing that matters in a view.

## 4. Hierarchy by plane, not by shadow.

The stone shows depth through facets — planes of slightly different warm gray. Flint does the same: background → surface → raised surface are steps on the warm ramp, separated by a **hairline border**, not a drop shadow. Shadows appear only for truly floating things (popovers, sheets), and stay faint. Depth is structural, not theatrical.

## 5. Dark-first; light is derived.

The icon was born in the dark, and so is Flint. Design and calibrate in dark mode first; light mode is a faithful derivation, not an afterthought, and it must pass the same accessibility bar (note the amber-on-white caveat in [COLOR.md](./COLOR.md)). Both ship; dark leads.

## 6. Soft outside, crisp inside.

The icon is a rounded squircle holding a sharp-edged stone. Flint mirrors that: outer containers (cards, sheets, popovers) use continuous (squircle) corners; the content they hold — the editor surface, the canvas — has crisp, near-zero-radius edges. Roundness frames; it never softens the work itself.

## 7. One look across two engines.

Flint's editor is CodeMirror in a WKWebView, wrapped in SwiftUI chrome — two render engines meeting at a visible seam. They must look like one app: identical color, type, and spacing on both sides. This is enforced structurally by **tokens-as-truth** (one JSON generating both `Tokens.swift` and `tokens.css` — see [README.md](./README.md)). Never define a color or size on only one side.

## 8. Native by default; branded by exception.

Respect Apple HIG and use system affordances (SF Symbols, system materials, standard navigation, Dynamic Type) unless there is a real reason not to. Flint's identity comes from the *palette, typography, and restraint* — not from re-skinning native controls. Fighting the platform is usually the wrong, higher-maintenance choice for a tool.

## 9. Motion is functional or absent.

Animation conveys spatial/state change (a panel sliding in, a thumbnail expanding to the canvas) — never decoration. Keep it short (120–320ms) and always honor Reduce Motion / `prefers-reduced-motion`. The same restraint governs **haptics** — the amber of touch, rare and semantic, and *never load-bearing* because the iPad has no Taptic Engine (see [INTERACTION.md](./INTERACTION.md)).

---

### Where the installed design *skills* apply (and where they don't)

Most installed skills (`taste-skill`, `frontend-design`, `brutalist`, `soft`, `minimalist`, `gpt-tasteskill`) are **web/landing-page** skills. They are **wrong for the native app** — their bold/editorial defaults violate §1. They are appropriate only for:

- styling the **CodeMirror CSS layer** (and even there, subordinate to these principles), and
- a future, **separate** marketing site.

For app UI, the relevant ones are `ui-ux-pro-max` / `design-system` (token + component reasoning, covers SwiftUI), `brand`/`brandkit` (identity, [ICONOGRAPHY.md](./ICONOGRAPHY.md)), and `imagegen-frontend-mobile` (screen concepts for exploration only — images, not code, kept local per [README.md](./README.md)).
