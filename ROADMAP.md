# Roadmap

> Build order follows "make it work → make it right → make it pluggable." The plugin system is **not** a final phase — it is the spine, and it is *extracted* once first-party features (Ink, Board, Flows) consume it. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/DECISIONS.md`](docs/DECISIONS.md).

## Phase 1 — MVP: native editor + Ink
**Goal:** an app the author uses daily instead of Obsidian iOS.

Built as **A → Ink** (A is a real milestone and the first half of the MVP).

**1a — Editor**
- [ ] Open the existing iCloud Obsidian vault; folder/note navigation
- [ ] Native-fluid Markdown editor (CodeMirror 6 via bridge)
- [ ] Full-text search (disposable FTS index)
- [ ] Frontmatter / tags; dark/light theme
- [ ] iCloud Drive sync (`iCloudDriveProvider`) with `.conflict` handling
- [ ] JS/native/bridge boundary designed from day 1 (no public Plugin API yet)

**1b — Ink** *(the differentiator)*
- [ ] `PKCanvasView` page (native palm rejection + low latency)
- [ ] 3-4 paper templates (lined, grid, dotted, blank)
- [ ] Save drawing as its own file (PKDrawing + PNG/SVG)
- [ ] Embed in notes via `![[sketch.ink]]`; editor shows thumbnail; tap opens canvas
- **Scope locked:** one page, save, embed, open. No infinite canvas/brushes/layers.

**Stack:** SwiftUI, PencilKit, WKWebView, CodeMirror 6, SQLite (FTS), iCloud Drive.

---

## Phase 2 — Plugin API extraction + Board & Flows
**Goal:** the community can extend the app; surfaces ship as first-party plugins.

- [ ] Extract the Plugin API with Ink (refactored), Board, Flows as first consumers
- [ ] Manifest + capability model, enforced at the bridge (`network` denied by default)
- [ ] **Board** — spatial map linking `.md` notes, in the open **JSON Canvas** format
- [ ] **Flows** — node graph orchestrating compute, with explicit routing
- [ ] Plugin API docs + porting guide for simple Obsidian plugins

**Stack:** WKWebView bridge, TypeScript SDK, JSON Canvas.

---

## Phase 3 — AI Integration
**Goal:** LLMs in note context, with explicit local/cloud/VPS routing.

- [ ] llama.cpp (Metal) + evaluate MLX; on-device model management
- [ ] Local-LLM node in Flows; cloud and VPS nodes
- [ ] Chat with current note as context; inline suggestions (complete, summarize, expand)
- [ ] Handle increased-memory entitlement + background suspension

**Stack:** llama.cpp, MLX, Metal, URLSession. (Local = light models only; heavy work routes out.)

---

## Phase 4 — Optional sync hub + Desktop + community
**Goal:** opt-in real-time sync and cross-platform reach.

- [ ] `ServerProvider` — self-hosted replication hub (user's PC / VPS / our paid VPS)
- [ ] Desktop app (Electron reusing the webview code)
- [ ] GitHub-based plugin marketplace
- [ ] (Eventual) multi-person collaboration as an evolution of the hub

**Stack:** replication hub (LiveSync/CouchDB model), Electron, TypeScript SDK.

---

*This roadmap is a living document and will be updated as the project evolves.*
