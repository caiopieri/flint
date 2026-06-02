# Flint — Architecture

This document is the engineering source of truth. For *why* each choice was made (and what was rejected), see [DECISIONS.md](./DECISIONS.md). For agent operating rules, see [`../CLAUDE.md`](../CLAUDE.md).

## Principles (these win conflicts)

1. **Local-first** — works fully offline, no Flint servers by default.
2. **`.md` files are the source of truth** — every DB is a disposable, rebuildable index.
3. **Single-user, multi-device** — collaboration is an optional future mode, not a base assumption.
4. **Plugins are the spine** — Ink, Board, Flows are first-party plugins.
5. **Native where it must be; web only for editor + plugin runtime.**
6. **Compute routing is explicit, never magic.**

## High-level layout

```
┌───────────────────────────────────────────────────────────┐
│                      Flint (SwiftUI host)                  │
│                                                            │
│   NATIVE (Swift)                       WEBVIEW (TS)        │
│  ┌────────────────────┐    bridge     ┌──────────────────┐ │
│  │ Vault (files=truth)│◄───────────── │ Editor (CodeMirror)│
│  │ Search (FTS index) │    typed      │ Plugin runtime    │ │
│  │ Sync (providers)   │ ────────────► │ Surfaces (logic)  │ │
│  │ Ink (PencilKit)    │               │  Ink/Board/Flows  │ │
│  │ AI (llama.cpp/MLX) │               └──────────────────┘ │
│  └────────────────────┘                                    │
│   bridge = security boundary (capability enforcement)      │
└───────────────────────────────────────────────────────────┘
```

## The boundary (most important section)

| Concern | Side | Notes |
|---|---|---|
| Markdown editing | **Webview** | CodeMirror 6 |
| Plugin logic | **Webview** | isolated WKWebView(s) |
| Flows graph definition/orchestration | **Webview** | the *definition*; execution of a node may call native |
| Surface view-logic (Ink/Board/Flows UI) | **Webview** | the canvas engine's interaction layer |
| UI panels | **Webview** | |
| Vault file I/O | **Native** | `FileManager` + `NSFileCoordinator`/file presenters |
| Search index | **Native** | SQLite FTS5, rebuildable |
| Sync | **Native** | `SyncProvider` protocol |
| Ink rendering | **Native** | `PKCanvasView` (PencilKit) |
| Local LLM execution | **Native** | llama.cpp (Metal) / MLX |
| Native-over-webview compositing | **Native** | e.g. opening the Ink canvas |

**Bridge contract**
- Typed, async, two-way message channel.
- Every `Flint.*` call from a plugin is checked against that plugin's declared permissions here.
- **APIs are coarse and async.** No per-keystroke / per-file chatter. A cached read-model (metadata index) is pushed into the webview once; plugins read it locally.

## Source of truth & storage

- **Truth:** `.md` files in the vault directory (iCloud container).
- **Search:** SQLite FTS5 — disposable, rebuildable from the vault. Never authoritative.
- **Disk access:** always through a `SyncProvider`. No scattered raw `FileManager` calls.
- Use `NSFileCoordinator` to coordinate with iCloud and detect external file changes.

## Sync

One consistency model (files-as-truth), two transports behind `SyncProvider`:

- **`iCloudDriveProvider`** (default, Phase 1): files live in the iCloud container; iCloud Drive syncs them. Offline↔offline conflict → **3-way merge**, falling back to a `.conflict` file when auto-merge fails. Zero server.
- **`ServerProvider`** (optional, future): a **dumb replication hub** (Obsidian Self-hosted LiveSync / CouchDB model). The server only relays; files stay canonical per device. Hub options: user's own PC, user's own VPS, or our paid VPS (far future). **This is the only place CRDT/chunked replication is legitimate.** Not in Phase 1.

Real-time multi-person collaboration, if ever, is an evolution of `ServerProvider` — not a new model in the base app.

## Plugin system

**Two tiers**
- **Web plugins** (community, TS): run in isolated WKWebView(s). Manipulate Markdown, read/write vault, inject UI, *call* native capabilities. Obsidian-style tier.
- **Native capabilities** (host / first-party Swift): PencilKit, local LLM, native compositing. Web plugins **drive** these via the bridge; they never implement them.

**Capability security model**
- Manifest declares perms: `storage:read`, `storage:write`, `ai`, `network`, `pencil`, `ui`.
- User grants at install; the bridge enforces each call.
- **`network` denied by default**, loud per-plugin grant (vault-read + network = exfiltration; unacceptable in a privacy-first app). Prefer routing plugin traffic through a user-visible proxy.

**Isolation (open implementation decision):** N webviews (strong isolation, memory cost → jetsam risk on iPhone) vs one shared webview + realms/workers (cheap, weaker isolation).

**Obsidian compatibility — strategy "B′":** own, clean API **modeled on Obsidian's conceptual shape** (`Vault`, `Command`, `Plugin` lifecycle, `MetadataCache` vocabulary) so *simple* plugins port by adaptation. **Not binary-compatible.** Complex plugins (Dataview, Excalidraw) are rewrites or first-party. Market as "familiar, easy to port simple plugins," not "Obsidian-compatible."

## Spatial surfaces

Three surfaces over **one low-level canvas engine** (viewport, pan/zoom, selection, hit-testing, edges). Each is a first-party plugin with its own node type:

| Surface | Nodes | Executable | Persisted as |
|---|---|---|---|
| **Ink** | strokes | no | PKDrawing (editable) + PNG/SVG (portable) |
| **Board** | note cards + links | no | **JSON Canvas** (jsoncanvas.org) |
| **Flows** | compute nodes | **yes** | JSON (format TBD) |

**Ink MVP = a separate embedded page**, not inline-in-text. Embed via `![[sketch.ink]]`; the editor renders a thumbnail widget (PNG exported by native side); tapping opens the native `PKCanvasView`. Inline Pencil-in-text compositing (native canvas over webview text with scroll-sync) is deferred — it is the hardest seam in the project.

**Flows execution is a security surface:** running a workflow is running code. Node execution (especially `network` and local-shell-like nodes) must respect the same capability model and be sandboxed. Design this when Flows is built.

## AI

- **Local on iPhone = light only.** The wall is **memory (jetsam)**, not heat. Fits and runs usably: ~1–8B Q4, or a small MoE whose *total* fits (~8–10 GB). Good for autocomplete, summarize, quick Q&A, offline, private. (MoE saves compute, **not** memory — all experts stay resident.)
- **Heavy work routes explicitly** via Flows to cloud (OpenAI/Anthropic) or the user's VPS. No automatic heuristic.
- **Stack:** llama.cpp (Metal) base; evaluate MLX. **Core ML is out** of the autoregressive LLM path.
- **iOS specifics:** `increased-memory-limit` entitlement; background suspension of long generations; model download/storage management (GBs each).

## Build order

"Make it work → make it right → make it pluggable." Build a monolithic core first (editor + vault + search) **without** a public Plugin API, but design the bridge boundary from day 1. **Extract** the Plugin API later with Ink/Board/Flows as the first consumers — the first plugin dev is the author, so the API is validated by real use, not guessed.

## Project structure

```
flint/
├── ios/                          # SwiftUI app (native host)
│   └── Flint/
│       ├── App/                  # shell, navigation
│       ├── Vault/                # files-as-truth I/O (FileManager + NSFileCoordinator + iCloud)
│       ├── Search/               # SQLite FTS index (disposable)
│       ├── EditorHost/           # WKWebView host + Swift side of the bridge
│       ├── Ink/                  # PencilKit (native capability)
│       ├── AI/                   # llama.cpp / MLX (local inference)
│       ├── Sync/                 # SyncProvider protocol; iCloudDriveProvider
│       ├── Bridge/               # typed JS<->Swift channel + capability enforcement
│       └── Plugins/              # plugin host, manifest/permissions
├── web/                          # code that runs INSIDE the webview (TS)
│   ├── editor/                   # CodeMirror 6 config + Markdown
│   ├── plugin-runtime/           # loader, sandbox, Flint.* API surface
│   └── surfaces/                 # canvas engine + Ink/Board/Flows view logic
├── plugins/                      # first-party plugins (after API extraction)
├── desktop/                      # Electron (later phase)
└── docs/                         # this file, DECISIONS.md
```
