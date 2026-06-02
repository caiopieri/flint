# Flint — Decision Log

Architecture Decision Records. Each entry: context, decision, rationale, and rejected alternatives. **Rejected alternatives are recorded so they are not silently reintroduced.**

---

## ADR-001 — `.md` files are the source of truth; SQLite is a disposable index

**Context.** The v0.1 PRD listed both "local `.md` vault" and "Core Data / SQLite" as the store, without resolving which is canonical.

**Decision.** Plain `.md` files in the vault directory are canonical. SQLite (FTS5) is a **derived, disposable** search index, rebuildable from the files.

**Rationale.** The product's premise is "replace Obsidian, privacy-first, plain files." A DB-as-truth model makes the vault an opaque `.sqlite`, breaking Obsidian/git interop and the privacy story.

**Rejected.** Core Data / SQLite as the authoritative store (Notion model). Killed: it contradicts files-as-truth and interop.

---

## ADR-002 — No CRDT in the base app; conflicts via 3-way merge + `.conflict`

**Context.** v0.1 specified Yjs CRDT for sync, justified as "the same tech Notion and Linear use."

**Decision.** The base app is single-user multi-device. Offline↔offline conflicts are handled by 3-way merge, falling back to a `.conflict` file. **No CRDT in Phase 1-2.**

**Rationale.** CRDT solves real-time multi-person collaboration — a requirement Flint does not have. It also pulls the sync engine into a JS/webview runtime. The justification was factually wrong: Notion is server-authoritative; Linear uses a custom sync engine; both are multi-person products.

**Rejected.** Yjs CRDT as the Phase 1-2 sync mechanism. CRDT is allowed **only** inside the optional future replication hub (ADR-003).

---

## ADR-003 — Sync: one model (files-as-truth), two transports behind `SyncProvider`

**Context.** Need cross-device sync now, and an optional "real-time like Notion" mode later, without breaking files-as-truth or the no-server promise.

**Decision.** All disk access goes through a `SyncProvider` protocol.
- `iCloudDriveProvider` (default, Phase 1): zero-server, file-level iCloud Drive sync.
- `ServerProvider` (optional, future): a **dumb replication hub** (Obsidian Self-hosted LiveSync / CouchDB model). Server only relays; files stay canonical per device. Hub = user's PC / user's VPS / our paid VPS (far future).

**Rationale.** The author's desired "real-time sync" is the LiveSync hub model, **not** Notion's server-as-truth. Files stay the truth; the server is a relay. This preserves both pillars. The abstraction costs ~nothing now and avoids scattering `FileManager` calls.

**Rejected.** Server-as-truth ("Notion mode") as a per-note toggle — it's a different consistency model and a different product mode, not a switch.

---

## ADR-004 — The WKWebView is only for editor + plugin runtime; sync and AI are native

**Context.** v0.1 put `editor/`, `sync/`, and `ai/` together in a shared TypeScript "core" (for eventual Electron reuse).

**Decision.** Only the editor (CodeMirror) and the plugin runtime live in the webview. **Sync and AI are native Swift.**

**Rationale.** Files-as-truth + iCloud is native iOS API (`FileManager`/`NSFileCoordinator`). llama.cpp/MLX are native binaries. Putting either in JS forces a webview↔native bridge for no benefit — fragile and slow. The only legitimate reason for the webview is the editor and JS plugins.

**Rejected.** A shared TS core containing sync/AI logic.

---

## ADR-005 — CodeMirror 6 in WKWebView is correct *because* plugins are core

**Context.** A fully-webview editor sacrifices native feel; a native (TextKit 2) editor avoids the PencilKit seam but loses the JS plugin ecosystem.

**Decision.** Use CodeMirror 6 in a WKWebView.

**Rationale.** Community plugins are central to the product, and that ecosystem is JS (Obsidian proved it). The webview is the right substrate for editor + plugins — a deliberate architectural choice, not laziness. The cost (Ink/PencilKit compositing seam) is deferred by ADR-007.

**Rejected.** A native TextKit-2 editor — loses the plugin story.

---

## ADR-006 — Plugins are the spine; the Plugin API is extracted, not designed up front

**Context.** v0.1 placed the plugin system in Phase 4, yet Ink (Phase 2) is itself a plugin.

**Decision.** Ink, Board, Flows are first-party plugins. Build a monolithic core first **without** a public Plugin API, design the bridge boundary from day 1, and **extract** the API once 2-3 first-party features consume it. Order: make it work → make it right → make it pluggable.

**Rationale.** Designing a plugin API in a vacuum (no real consumer) is the #1 cause of plugin-API rot. The first plugin dev is the author; the API is validated by real use.

**Rejected.** Plugin system as the final phase; freezing a public API before first-party consumers exist.

---

## ADR-007 — Plugin tiers + capability security; Obsidian "familiarity," not compatibility

**Context.** "Sandbox" plugins that can't read the vault are useless; full-trust plugins (Obsidian model) can exfiltrate notes. Also: "plugins like Obsidian" is ambiguous between *familiar* and *binary-compatible*.

**Decision.**
- Two tiers: **web plugins** (JS, isolated webview, call native via bridge) and **native capabilities** (Swift; web plugins drive but don't implement).
- **Capability model:** manifest perms (`storage:read/write`, `ai`, `network`, `pencil`, `ui`), granted at install, enforced at the bridge. **`network` denied by default**, loud per-plugin grant.
- **Strategy "B′":** own clean API modeled on Obsidian's *conceptual shape*; simple plugins port by adaptation. **Not binary-compatible.** Market as "familiar," never "compatible."

**Rationale.** The bridge is already a chokepoint, so capabilities are nearly free and fit privacy-first. Binary Obsidian compat is a trap — their API is huge, Electron/DOM-bound, mobile-hostile, and a moving target. The draw for devs is native capabilities Obsidian can't offer.

**Rejected.** Obsidian-style full-trust plugins; binary Obsidian-plugin compatibility.

**Open.** Isolation strategy — N webviews vs shared webview + realms/workers (memory vs isolation trade-off on mobile).

---

## ADR-008 — Three spatial surfaces over one canvas engine; Ink MVP is a separate embedded page

**Context.** "Canvas" conflated three different things: handwriting, a note-linking map, and an executable workflow graph.

**Decision.** One low-level canvas engine (viewport/pan/zoom/selection/edges) + three node-type packages: **Ink** (strokes), **Board** (note cards, **JSON Canvas** format), **Flows** (compute nodes, executable). **Ink MVP is a separate embedded page** (`![[sketch.ink]]`), not inline-in-text.

**Rationale.** The three share only `(x, y)`; their node semantics differ wildly — one god-component would be bad at all three. Board on JSON Canvas keeps Obsidian interop. Embedding Ink as its own file avoids the native-canvas-over-webview compositing seam (the hardest part) and honors files-as-truth (the drawing is its own file). PencilKit gives palm rejection/latency/tools for free, so a basic canvas is little code; the real risk is scope creep — MVP Ink = one page, save, embed, open.

**Rejected.** A single unified canvas; inline Pencil-in-text compositing in the MVP; a proprietary Board format.

---

## ADR-009 — AI: local is light; routing is explicit; heat is not a constraint, RAM is

**Context.** v0.1 promised "run a 3B model without overheating," "<5s," and "automatic local/cloud routing."

**Decision.** Local on iPhone = light models only (~1–8B Q4, or a small MoE whose total fits ~8–10 GB). Heavy work routes **explicitly** via Flows to cloud or the user's VPS. Stack: llama.cpp (Metal) + evaluate MLX; **Core ML out** of the LLM path.

**Rationale.** The binding limit is memory (jetsam), not heat — heat is a normal consequence and iOS already throttles/jetsams. MoE saves compute, not memory (all experts resident; routing is per-token). "Automatic" routing is impossible — you can't know task difficulty before running. Explicit routing in the Flows graph is better and simpler. (Verified the "iPhone 17 Pro Max ran a 400B model" claim: it's flash-streaming at 0.6 tok/s — a demo, not usable; 12 GB RAM ≈ 6% of the model's needs.)

**Rejected.** "No overheating" as a goal; automatic local/cloud routing; Core ML for autoregressive LLMs; expecting hundreds-of-billions-parameter models to run usably on-device.

---

## ADR-010 — MVP = native editor + Ink, built as A → Ink

**Context.** A pure native-editor MVP may not be enough to leave mature Obsidian iOS (high switch cost, low benefit — the "valley of death").

**Decision.** MVP is option **B** (editor + Ink), but built as **A then Ink**, not A-vs-B. A = native files-as-truth editor over the existing iCloud vault (nav, edit, search, frontmatter/tags, dark/light, iCloud sync) — a real milestone and the fallback daily-driver. Ship as v1 only when Ink lands.

**Rationale.** A is literally the first half of B, so this isn't skipping steps. The early differentiator (Ink) crosses the valley; A de-risks it (if Ink stalls, there's still a usable editor). De-risking Ink to a separate embedded page makes B ≈ A + 20-30%, not 2×.

**Rejected.** Shipping a pure-editor MVP and hoping it's enough to switch; attempting full Ink (infinite canvas/brushes/layers) in the MVP.

---

## ADR-011 — Vault access via document picker + security-scoped bookmark, not an iCloud container

**Context.** The goal is to open the author's **existing** Obsidian vault, which lives inside Obsidian's own iCloud container (`iCloud~md~obsidian/...`). It is tempting to "just use iCloud" by giving Flint its own iCloud container.

**Decision.** Flint opens a **user-chosen folder** via the document picker (`.fileImporter` / `UIDocumentPickerViewController`) and persists a **security-scoped bookmark** to it. All access goes through `NSFileCoordinator`/`NSFilePresenter`. Flint does **not** use its own iCloud container for the vault and does **not** assume the vault is in iCloud at all.

**Rationale.** iOS sandboxing means an app **cannot read another app's iCloud container** — Flint can never reach Obsidian's container directly. A document-picked folder + security-scoped bookmark is the only way to open an arbitrary existing vault (Obsidian's iCloud folder, a local folder, a Working Copy repo, etc.). It also keeps files-as-truth honest: the vault is wherever the user keeps it, not a Flint-owned silo. "Sync" is whatever that folder already has (iCloud Drive, etc.), surfaced through `SyncProvider`.

**Rejected.** A Flint-owned iCloud/CloudKit container as the vault home (can't open existing vaults; silos the user's notes); assuming the vault is always in iCloud.

**Implication.** The `Vault` module starts from a bookmark, not a fixed path. Handle bookmark staleness/re-resolution and the `startAccessingSecurityScopedResource` lifecycle.

---

# Design ADRs

Decisions about the visual/interaction system. Full system in [`design/`](./design/). Same format: context, decision, rationale, rejected alternatives.

---

## ADR-D01 — The design system is derived from the app icon

**Context.** The repo had zero design consolidation — no colors, type, or styles — while an app icon already existed (`assets/brand/flint-icon.svg`), made by the author.

**Decision.** Derive the entire system from the icon: warm near-black field, a warm-gray faceted stone, and a rare amber spark. Concretely → warm-neutral ramp (no cold/blue gray), a single amber accent used sparingly, hierarchy by surface plane + hairline (not shadow), dark-first.

**Rationale.** The icon is already a coherent, opinionated statement; deriving from it guarantees the product and its mark agree, and avoids inventing an unrelated palette. It also matches the product ethos (calm, content-first tool — not a flashy site).

**Rejected.** A generic SaaS/Material palette; importing the aesthetics of the installed web-design skills (`taste-skill`, `brutalist`, etc.) — those are landing-page skills, wrong for a native long-form tool.

---

## ADR-D02 — Amber is the accent, but accent *text* darkens in light mode

**Context.** The icon's amber `#EF9F27` is the brand spark, beautiful on dark. But it only reaches ~2.2:1 on white — failing WCAG AA for text.

**Decision.** Keep `#EF9F27` for fills/icons/cursor in both modes. For amber **text/links in light mode**, use the darkened `spark.800` (`#9A6206`, ~5.1:1). This is the one place the palette diverges by mode (`accent` vs `accent-text`).

**Rationale.** Preserves the brand spark where contrast rules are lenient (non-text) while meeting AA where they aren't (text). Honesty about contrast is required for a reading app (see `design/ACCESSIBILITY.md`).

**Rejected.** Using `#EF9F27` for light-mode link text (fails AA); abandoning amber text entirely (loses the brand cue).

---

## ADR-D03 — tokens-as-truth: one JSON generates both Swift and CSS

**Context.** Flint's UI spans two render engines — SwiftUI chrome and CodeMirror inside a WKWebView — meeting at a visible seam. Maintaining color/type/spacing separately in Swift and CSS guarantees drift, and a mismatched seam.

**Decision.** A single source of truth, `docs/design/tokens/tokens.json`, is compiled by `scripts/gen-tokens.mjs` into `ios/Flint/App/Tokens.swift` and `web/src/tokens.css`. The two generated files are **gitignored** (rebuildable, like `Info.plist`/`.xcodeproj`/the web bundle). No color or size is ever defined on only one side.

**Rationale.** Mirrors the repo's files-as-truth discipline: one canonical artifact, disposable generated indexes. It is the structural enforcement of "one look across two engines" (`design/PRINCIPLES.md §7`) — parity by construction, not by vigilance.

**Rejected.** Hand-maintaining parallel Swift and CSS palettes; committing the generated files (contradicts the repo's generated-files-are-ignored convention).

**Implication (for implementation).** Wire `node scripts/gen-tokens.mjs` into `make bootstrap` and an Xcode pre-build phase so a fresh clone builds. Design is complete; this wiring is left to the dev.

---

## ADR-D04 — Native typefaces only: New York (reading) / SF Pro (UI) / SF Mono (code)

**Context.** A note app's reading face is its most important type decision, and the editor lives in a webview while the chrome is native — fonts must match across the seam.

**Decision.** Three Apple-native, zero-bundle families: **New York** (`.serif` / `ui-serif`) for editor reading text, **SF Pro** (system / `ui-sans-serif`) for UI chrome, **SF Mono** (`.monospaced` / `ui-monospace`) for code. Serif content + sans chrome (the iA Writer lineage).

**Rationale.** `ui-serif` resolves to New York on Apple platforms, so the webview editor and native chrome render identical fonts with no webfont, no FOUT, no licensing, no bundle weight. A serif makes the editor read as a document, not a form — calm and editorial, matching the warm palette.

**Rejected.** A bundled custom/Google webfont (bundle weight, licensing, seam-matching pain); an all-sans system (loses the editorial reading feel); a serif for chrome (controls should feel native).
