# Flint — Implementation Tasks

The concrete, ordered plan for building the **Phase 1 MVP**. Read [`../AGENTS.md`](../AGENTS.md) and [`ARCHITECTURE.md`](./ARCHITECTURE.md) first — this file assumes those invariants and the boundary.

## How to work through this

- **Do it in order.** Tasks are sequenced so each builds on a working previous step. Don't jump ahead.
- **One task group = one branch + PR.** Never commit feature work straight to `main`.
- **Vertical slices.** Prefer "thin thing that works end-to-end" over "whole layer, untested."
- **Respect the scope locks.** Especially: no public Plugin API in Phase 1; Ink MVP = one page, save, embed, open. If a task tempts you past a lock in AGENTS.md, stop and flag it.
- A task is done only when its **DoD (Definition of Done)** is met — not when the code compiles.

---

## Locked setup decisions

Change these only with the author's sign-off (some are noted as the author's call).

| Area | Decision | Notes |
|---|---|---|
| **Min iOS** | **iOS 26.0** | Personal-first → latest only, full access to the newest SwiftUI/PencilKit APIs. (Author has all current devices.) |
| **Language** | **Swift 6**, strict concurrency (complete) | New project; adopt it from day 1 rather than migrate later. |
| **Xcode** | Latest stable | |
| **Native deps** | **SwiftPM only.** Start with **GRDB** (SQLite FTS5). Keep deps minimal. | No CocoaPods/Carthage. |
| **Search store** | **SQLite FTS5 via GRDB** | Disposable, rebuildable index. Never the source of truth. |
| **Web toolchain** | **TypeScript + esbuild**, npm. Output one bundled JS/CSS/HTML into app resources. | The `web/` build is copied into the iOS bundle at build time. |
| **WebView loading** | **Custom `flint://` scheme** via `WKURLSchemeHandler` | Not `file://` (avoids quirks, cleaner asset serving, tighter origin). |
| **Bridge** | `WKScriptMessageHandlerWithReply` (JS→Swift async). Typed envelope `{ id, method, payload }`. | Coarse, async APIs only — see AGENTS.md performance rule. |
| **Vault access** | **Document picker + security-scoped bookmark** to a user-chosen folder | See **ADR-011**. We do NOT use our own iCloud container and CANNOT read Obsidian's container. |
| **Network** | **None in the app target for Phase 1** | Privacy-first; nothing leaves the device. |

---

## Prerequisites & build

- **Xcode** (latest), **XcodeGen** (`brew install xcodegen`), **Node** (for the `web/` bundle).
- The Xcode project is **generated** from `ios/project.yml` (not committed). Entry points via `make`:
  - `make bootstrap` — install web deps, build the bundle, generate `ios/Flint.xcodeproj`
  - `make build` — build the web bundle + the app for the iOS Simulator
  - `make open` — generate + open in Xcode
- Edit project structure/settings in `ios/project.yml`, never in the generated `.xcodeproj`.

## Phase 1a — Native editor (the first half of the MVP, a real milestone)

### T0 — Project scaffold ✅ (done)
- [x] T0.1 Xcode SwiftUI app (iOS 26, Swift 6, strict concurrency) via XcodeGen. Native folder structure from `ARCHITECTURE.md`: `App/`, `Vault/`, `Search/`, `EditorHost/`, `Sync/`, `Bridge/` + stubbed `Ink/`, `AI/`, `Plugins/`.
- [x] T0.2 `web/` (TypeScript + esbuild) producing a bundle, copied into the app's resources by `scripts/build-web.sh` (also an Xcode pre-build phase).
- **DoD met:** `make build` → **BUILD SUCCEEDED** for the simulator; the web bundle ships inside `Flint.app/web/`; empty SwiftUI shell.

### T1 — Vault (files-as-truth)
- [ ] T1.1 Folder picker (`.fileImporter`) to choose the vault folder; persist a **security-scoped bookmark**; resolve it on launch.
- [ ] T1.2 Enumerate folders/`.md` files under `NSFileCoordinator`; build an in-memory tree for navigation.
- [ ] T1.3 Coordinated read of a note's text; coordinated write-back. Observe external changes (`NSFilePresenter`) and refresh.
- **DoD:** pick your real Obsidian vault folder, see the folder/note tree, open a note and see its text; an external edit (e.g. on Mac) shows up.

### T2 — SyncProvider abstraction
- [ ] T2.1 Define the `SyncProvider` protocol (`list`, `read`, `write`, `watch`, `resolveConflict`). **All vault access from T1 routes through it.**
- [ ] T2.2 Implement `iCloudDriveProvider` over T1 (files in an iCloud-synced folder; "sync" is iCloud + conflict handling).
- [ ] T2.3 Conflict handling: detect iCloud conflict versions (`NSFileVersion`) → attempt 3-way merge → fall back to a `.conflict` sibling file. **Never silently lose an edit.**
- **DoD:** no raw `FileManager` calls leak outside the provider; a simulated two-device offline edit yields either a clean merge or a `.conflict` file.

### T3 — Editor (CodeMirror in WKWebView) + Bridge
- [ ] T3.1 `EditorHost`: a `WKWebView` serving the bundle via the `flint://` scheme handler. Prove the **bridge** first with a trivial echo (JS `bridge.call("ping")` → Swift → reply).
- [ ] T3.2 Bridge methods `doc.load(path)` and `doc.save(path, text)` wired to `SyncProvider`. Typed envelope; debounced saves.
- [ ] T3.3 CodeMirror 6 in `web/editor/` with the Markdown language + dark/light theme. Load note text on open; emit debounced changes → `doc.save`.
- **DoD:** open a note → edit in CodeMirror → changes persist to the `.md` on disk → reopening shows the saved text.

### T4 — Full-text search
- [ ] T4.1 `Search` module: SQLite FTS5 (GRDB) indexing path/title/body of every `.md`. Rebuildable from the vault.
- [ ] T4.2 Build the index on first launch; update incrementally on file change (via the `SyncProvider` watch).
- [ ] T4.3 Search UI: query → ranked results → open note.
- **DoD:** a query returns matching notes and opens them; deleting the index file and relaunching rebuilds it with no data loss (proves it's disposable).

### T5 — Frontmatter, tags, theme
- [ ] T5.1 Parse YAML frontmatter; surface `tags`; basic tag list/filter.
- [ ] T5.2 Dark/light theme wired through both the native shell and CodeMirror, following system appearance.
- **DoD:** a note with frontmatter shows its tags; toggling system appearance updates the editor too.

**Phase 1a complete when:** you can open your real vault, navigate, edit `.md` natively and fluidly, search, see tags, and trust sync not to lose edits — i.e. it's already a usable daily Markdown editor.

---

## Phase 1b — Ink (the differentiator that completes the MVP)

> Scope is **locked**: one page, paper templates, save, embed, open. **No** infinite canvas, custom brushes, or layers. See ADR-008.

### T6 — Ink canvas
- [ ] T6.1 A native `PKCanvasView` page (palm rejection/latency come free from PencilKit) with a tool picker.
- [ ] T6.2 3-4 paper templates (lined, grid, dotted, blank) as the canvas background.
- [ ] T6.3 Save the drawing as its own vault file: **PKDrawing** (editable source) **+** a rendered **PNG/SVG** (portable).
- **DoD:** draw a page, save it; reopening loads the strokes for further editing; the PNG exists alongside.

### T7 — Editor ↔ Ink seam
- [ ] T7.1 Embed syntax `![[sketch.ink]]` written into the note on save.
- [ ] T7.2 CodeMirror widget decoration renders the embed as a **thumbnail** (the native-exported PNG, fetched over the bridge).
- [ ] T7.3 Tapping the thumbnail opens the native Ink canvas for that file.
- **DoD:** from a note, create an Ink page, see its thumbnail inline, tap to reopen and edit it. This is the first and only editor↔Ink integration point — test it hard.

**MVP (v1) ships when 1a + 1b are done and the author uses Flint daily instead of Obsidian iOS.**

---

## Out of scope for Phase 1 (do NOT start these)

Public Plugin API · Board · Flows · AI/local LLM · the sync hub (`ServerProvider`) · desktop · inline Pencil-in-text compositing. These come in later phases (see `ROADMAP.md`). Building them now is scope creep.
