# ROADMAP — Flint

> The layer **above** the spec. The spec-kit slices *one* feature; this file decides *which* slices, *in what order*, across the whole product. Format: **Now / Next / Later** (by horizon, not date). Each "Now" item is a slice that fits the spec-kit flow (`/speckit.specify` → … → `/speckit.implement`). Living document — update it when reality changes.
>
> **Product vision (north star):** `Ideaverse/2. Pessoal/Flint.md` says *what Flint is* end-to-end. This roadmap is the *build order* — a disciplined re-slicing of that vision. The vision's broad "Núcleo v1" is split here into thin vertical slices. AI is core to the product's **identity**, but it enters the **build** as an early thin slice, not all at once. Engineering rationale: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) · [`docs/DECISIONS.md`](docs/DECISIONS.md).

## Estado atual

The **editor track ("A" from ADR-010) is substantially built**: opens a user-chosen vault (document picker + security-scoped bookmark), folder/note navigation, native-fluid Markdown editing with live preview (CodeMirror 6 over the `flint://` scheme + typed bridge), full-text search (SQLite FTS5 via GRDB — built and tested), frontmatter/tags, iCloud Drive sync with 3-way merge (`Diff3`) + `.conflict` fallback, dark/light theme, and the full design system + tokens pipeline.

**Ink, AI, and Plugins are stubs** (~10 lines each). The app is not yet a daily-driver — remaining editor gaps for full Obsidian-iOS replacement are to be confirmed (see Next #1). Legacy artifacts: old-format specs in `docs/specs/_legacy/`, Phase-1 tracker in `docs/TASKS.md`.

## Now (in flight — max 1-2 slices)

- [ ] **Ink MVP** — tier **T1**. The differentiator; the slice that crosses the "valley of death" (ADR-010: ship v1 when Ink lands). `PKCanvasView` page (native palm rejection + low latency), 3-4 paper templates (lined/grid/dotted/blank), save a drawing as **its own file** (PKDrawing + PNG/SVG), embed in notes via `![[sketch.ink]]` (editor shows a thumbnail; tap opens the native canvas).
  - **Riskiest hypothesis it attacks:** native ink *as a separate embedded page* is good enough to leave GoodNotes/Obsidian, and the embed seam works **without** the inline native-over-webview compositing nightmare (deferred by design, ADR-008).
  - **Scope locked:** one page, save, embed, open. **No** infinite canvas / brushes / layers.
  - Spec: `specs/001-ink-mvp/`.

## Next (prioritized queue — enters when Now empties)

1. **Editor → daily-driver** — tier **T1**. Close whatever's missing for the author to fully replace Obsidian iOS for read/edit (confirm gaps: wikilink navigation, embed rendering, attachments, outline). *Scope to be pinned in Discovery before it enters Now.*
2. **AI — first thin slice** — tier **T1**. **Not** the full agent: "search my vault (*where did I write about X*) + summarize / chat with the current note as context." Local light model by default; optional user-supplied API key (e.g. OpenRouter) in settings. Validates the **context harness** early without inflating scope — this is the bridge between the vision's "AI as the operating layer" and the discipline of a thin slice. **Design the AI as a provider-agnostic layer from day 1:** the on-device model is the default provider; a user API key and, later, a connected **Jarvis** engine are pluggable providers behind the same interface. Cheap to design now, expensive to retrofit (same logic as designing the bridge boundary up front, ADR-006).
3. **Board (linked-note canvas) — arrange/view MVP** — tier **T1**. Spatial map of `.md` notes in the open **JSON Canvas** format (jsoncanvas.org), over the low-level canvas engine. First-party surface; **does not** require the public Plugin API yet (ADR-006). The "canvas conectado" of the vision, as a first consumer of the engine.

## Later (captured, not committed)

- **Plugin API extraction** — *depends on:* Ink + Board (+ Flows) existing as first-party consumers (ADR-006). Manifest + capability model enforced at the bridge; `network` denied by default (ADR-007).
- **Flows** — executable workflow node graph; the vision's *"grafo de workflows."* Flint as a **client** of the headless [[Meta-fábrica]] engine — starts as a *viewer* of engine state, not an authoring tool. *Depends on:* canvas engine + Plugin API + the engine existing. Security surface (sandboxed execution).
- **Full AI agent** — tools to manipulate the canvas, create files, transcribe audio, tiered local↔API orchestration. *Depends on:* the AI thin slice validating + canvas surfaces existing.
- **Jarvis as the AI provider** — connect the headless home **Jarvis** engine (running on the home PC) as the most powerful AI provider, over MCP. The on-device model becomes Jarvis's *local/fast node* and delegates heavy work — deep research, home control, [[Meta-fábrica]] routing — to the home engine when reachable (Jarvis's own "LLMs em camadas," with the iPhone as a node). **Flint *connects to* Jarvis; it never contains it.** If Jarvis is never configured, Flint's AI stays vault-only. *Ownership contract:* Flint owns the UI, the on-device runtime, the vault tools, and the bridge/capability security; Jarvis owns orchestration, the MCP-of-MCPs, home control, and Meta-fábrica routing; the seam between them is MCP. *Depends on:* Jarvis existing + the provider-agnostic AI layer + the MCP/plugin layer. **Security:** an AI that can touch every file *and* control the house is the project's most sensitive capability boundary — see `docs/constitution.md`.
- **App canivete** — no-code UI builder (button/chart/list, wired to data). *Depends on:* Board/Flows + Plugin API. When it exists, the agent gains the "plan-and-build-a-UI" tool.
- **Optional sync hub + Desktop + marketplace** — `ServerProvider` (LiveSync/CouchDB-style dumb replication hub: user's PC / VPS / our paid VPS), Electron desktop reusing the webview, GitHub-based plugin marketplace. *Depends on:* a stable core. CRDT is legitimate **only** here (ADR-002/003).
- **Home-storage client (NAS / OneDrive replacement)** — browse the home server's *full* storage (media, large files) from Flint. This is a **remote-access/streaming** model, **distinct** from vault replication — you don't replicate terabytes to a phone, so it's a different consistency model (don't conflate them; ADR-002/003). *Approach:* the home box runs a standard self-host (Nextcloud / WebDAV / Syncthing / SMB) surfaced to iOS via **Files.app + a File Provider extension**; Flint stays a *client*. The vault itself can already live on that storage via the user-chosen folder (ADR-011). A general file browser, if any, ships as a **plugin/activatable tab — never native spine** (it competes with Files.app/Synology/Nextcloud; not Flint's moat). *Depends on:* the home server + the plugin layer.
- **Opt-in E2EE cloud backup** — client-side-encrypted backup so even a hosted service literally cannot read it (privacy promise preserved on someone else's servers). **BYO-cloud** (S3 / Backblaze / Drive) first — the cheap step; a **paid hosted tier** later — which adds a real durability/availability obligation (T2-grade ops + liability; "we promise peace of mind" is a promise with teeth). *Depends on:* a stable vault + the encryption layer.
- **Live process map** — nodes pulse as agents work; the Meta-fábrica panel, alive. *Depends on:* the Meta-fábrica engine.

## Sequencing principles (this project)

- **Vertical slice, not horizontal layer.** Each item delivers value end-to-end, mirroring the spec-kit's independent P1/P2/P3 stories.
- **The first slice attacks the riskiest hypothesis** (from Discovery), not the easiest.
- **Consolidate before advancing.** A shipped slice with a bug becomes "Now" again — don't stack on an unstable base.
- **The Plugin API is extracted, not designed up front** (ADR-006): build first-party surfaces, extract the API once 2-3 consume it.
- **Ink scope stays locked** (one page, save, embed, open) until v1 ships.
- **Tier promotion (T1 → T2) is a conscious decision** with its own roadmap entry, never by inertia — hardened slice by slice before any public launch.
- **Heavy capabilities live in headless engines Flint connects to** — the sync hub, [[Jarvis]], the Meta-fábrica engine — never bolted into the app binary. Flint is a client/surface. This is the discipline that stops Flint from sprawling into a do-everything app (NAS + backup service + home control + notes in one binary).
