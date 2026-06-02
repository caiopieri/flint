# Flint — Components (Phase 1)

The surfaces the MVP needs, with specs and states, mapped to [`../TASKS.md`](../TASKS.md). Scope is **Phase 1a (editor) + 1b (Ink)** only — no Board/Flows/AI/plugin UI here. Every value references a token; if a needed value isn't a token yet, add it to `tokens.json` rather than hard-coding.

General rules: hairline borders (`border` / `border-subtle`) instead of shadows for structure (§4); continuous corners on containers, crisp content (§6); amber only on the active/primary element (§3).

---

## Navigation shell  · T1

The app frame, chosen by width (both match Obsidian).
- **iPhone (compact): a push drawer** — the file tree shoves the note aside (it does **not** overlay), opened by a toolbar toggle or edge-swipe and dismissed by tapping/swiping the pushed note. A phone has no room for a side-by-side sidebar.
- **iPad (regular): an overlay** — the tree floats *over* a full-width note behind a light scrim (`black` @ ~12%), slides in from the leading edge, and dismisses on scrim tap, toggle, or selecting a note. The scrim + a `border` hairline on its trailing edge separate it from the note — **no shadow** (§4). The iPad has room, so the note never gets squeezed; the sidebar is summoned and dismissed.

The top bar shows the open note's name, or nothing. Both shells own exactly **one** sidebar toggle (a hand-rolled layout, not `NavigationSplitView`, whose injected toggle couldn't be removed).

The **vault name lives in the sidebar header** (tap → switch/open another vault). Next to it, three icon buttons: **sort** (`arrow.up.arrow.down` → a menu: Name A–Z/Z–A, Modified newest/oldest, Created newest/oldest — folders always first; the choice is persisted), **new folder** (`folder.badge.plus`), and **new note** (`square.and.pencil`). There is no separate overflow menu, and no manual reload — the vault refreshes itself via the file presenter.

Expanding a folder rotates its chevron and reveals children with a fade+slide (`motion.base`), not an abrupt row-pop.

- **Background:** `bg`. **Sidebar:** `surface`, divided from detail by a `border` hairline.
- **Folder/note tree:** rows at `space-2` vertical padding, `space-4` leading inset per depth level. Disclosure chevrons use SF Symbols in `text-muted`.
- **Selected row:** `surface-raised` fill, `radius-sm` continuous, with the label in `text-primary`. The selection indicator is a 2px `accent` bar on the leading edge — the spark marking "you are here." No full amber fill.
- **Note row:** title in `ui.body`/`text-primary`; optional secondary line (`ui.caption`/`text-muted`).
- **Empty state (no vault yet):** centered, the flint mark + one sentence + a single primary button "Choose vault folder" (see Buttons). This is the `.fileImporter` entry from T1.1.

## Editor  · T3

The core surface. CodeMirror 6 in the WKWebView, themed entirely by `tokens.css`.

- **Editor background:** `bg` (must match the native chrome's `bg` exactly — same token, both engines). **Text:** `reading.base` serif, `text-primary`.
- **Column:** centered, max width `reading-measure` (68ch); generous horizontal padding (`space-5`+) so text never kisses the edge.
- **Caret:** `cursor` (amber) — the literal spark. **Selection:** `selection` (translucent amber).
- **Markdown rendering:** per the syntax palette in [COLOR.md](./COLOR.md). Markup characters dimmed to `text-muted`; headings/strong by weight; links & tags in `accent-text`; code on `surface-raised`.
- **Crisp content (§6):** the editor area itself has `radius-none`. Rounding lives on the chrome around it, not on the writing surface.
- **States:** focused (caret visible), unfocused (caret hidden, selection dimmed). No focus glow.

## Search  · T4

- **Entry:** a search field in the sidebar/toolbar. Field: `surface-raised`, `radius-md`, `border-subtle`, leading `magnifyingglass` SF Symbol in `text-muted`, placeholder in `text-muted`.
- **Results:** list of rows — title (`text-primary`), path (`text-muted`/`ui.caption`), and a snippet with the **matched term in `accent-text`** (not highlighted background — colored text, restraint). Ranked; tap opens the note.
- **Empty/no-results:** quiet centered `text-secondary` line. No illustration.

## Frontmatter & tags  · T5

- **Tags:** rendered as inline chips — `surface-raised` fill, `radius-sm`, label in `accent-text`, `ui.caption`. Tags are navigational sparks, so amber is correct here.
- **Tag filter:** a list/flow of tag chips; the active filter chip gets an `accent` 2px underline or border, not a full fill.
- **Frontmatter block:** shown subtly above the body — `text-secondary`, slightly smaller; visually distinct from body but not loud.

## Buttons & controls

Tools, not a marketing site — keep these calm.

- **Primary (rare — one per view max):** `accent` fill, `text` = `bg` (dark text on amber for contrast in both modes — verify per use), `radius-md` continuous, ≥44pt tall. This is the spark; there should almost never be two on screen.
- **Secondary:** `surface-raised` fill, `text-primary`, `border` hairline, `radius-md`.
- **Tertiary / icon button:** no fill; SF Symbol in `text-secondary`, → `text-primary` on press. ≥44×44pt tap target even if the glyph is smaller.
- **Toggle/switch:** native; tinted `accent` when on.
- **Press feedback:** every button gets a visual press state — scale **0.97** + one-step fill shift over `motion.fast` (works on iPad and in the webview). Haptics are an iPhone-only enhancement layered on top and are *never* the sole feedback — full allowlist and the iPhone/iPad/Pencil limits are in [INTERACTION.md](./INTERACTION.md).

## Theme switching  · T5.2

Follows system appearance by default (dark-first identity, but respects the OS). Both engines flip together: the native side via `userInterfaceStyle`, the webview via `prefers-color-scheme` (and `[data-theme]` when forced). Because both read the same generated tokens, they switch in lockstep — test that the seam doesn't flash mismatched colors during the transition.

---

## Ink — canvas  · T6

Native `PKCanvasView`. Scope-locked: one page, save, embed, open (ADR-008). No infinite canvas/brushes/layers.

- **Canvas background:** `paper-background`; rule lines/dots in `paper-rule` (faint).
- **Paper templates (3–4):** `blank`, `lined`, `grid`, `dotted`. Rule spacing on the 4pt grid (e.g. lined = 32pt rhythm). Templates are a background layer; strokes draw above.
- **Tool picker:** prefer the system `PKToolPicker`. If a custom bar is needed, it sits on `surface` with a `border` top hairline, icon buttons per the icon-button spec, the active tool marked with an `accent` indicator.
- **Chrome:** minimal top bar — back/done (`text-primary`), template switcher, undo/redo. `surface` background, `border` hairline. The canvas itself is edge-to-edge and crisp (§6).
- **States:** drawing, idle, saving (a quiet `text-muted` indicator — never a blocking spinner for a local save).
- **Haptics:** this is the *only* surface where iPad tactile feedback exists — a snap to a template grid/line or ruler fires `UICanvasFeedbackGenerator` with Apple Pencil Pro. See [INTERACTION.md](./INTERACTION.md).

## Ink — embed thumbnail  · T7

The one and only editor↔Ink integration point — get it right.

- In the editor, `![[sketch.ink]]` renders as a **CodeMirror widget**: the native-exported PNG inside a container with `surface-raised`, `border`, `radius-md` continuous, modest max-height. A small `pencil.tip` SF Symbol corner badge in `text-muted` signals "handwritten, tap to edit."
- **Loading:** placeholder box at the final size (reserve space, no layout shift — CLS discipline) in `surface-raised` with a faint `text-muted` label.
- **Tap:** opens the native `PKCanvasView` for that file (native-over-webview composite). Use a short `motion.base` transition (respect Reduce Motion).

---

## Token quick-reference

| Need | Token |
|---|---|
| App / editor background | `FlintColor.bg` / `--flint-bg` |
| Panel, sidebar | `surface` |
| Card, popover, chip, code bg | `surface-raised` |
| Divider | `border` / `border-subtle` |
| Body text | `text-primary` |
| Labels, metadata | `text-secondary` |
| Dimmed (markup, hints) | `text-muted` |
| The one active/primary thing | `accent` |
| Amber link/tag text | `accent-text` (darkens in light mode) |
| Caret / selection | `cursor` / `selection` |
| Spacing | `space-1..10` (4pt grid) |
| Container corners | `radius-sm/md/lg` (continuous) |
| Content corners | `radius-none` |
