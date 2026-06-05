# Flint — Agent & Contributor Guide

Flint is an open-source iOS/iPadOS note app: the depth of Obsidian (Markdown, local vault, plugins), native Apple Pencil handwriting, and local/cloud AI — privacy-first, local-first.

This file is the entry point for any agent or contributor. **Read next:** `docs/ARCHITECTURE.md` (how it's built) and `docs/DECISIONS.md` (why, and what NOT to reintroduce). For anything visual, `docs/design/` is the design system (start at `docs/design/README.md`).

---

## Non-negotiable invariants

These override convenience. If a task conflicts with them, stop and flag it.

1. **Local-first.** The app works fully offline. **No Flint servers in the default path.**
2. **`.md` files are the source of truth.** The vault is a directory of plain text files any tool (Obsidian, git) can read. **Every database is a disposable, rebuildable index — never the source of truth.**
3. **Single-user, multi-device.** Offline iPhone/iPad conflict, not multi-person collaboration. Collaboration is an optional, future, opt-in mode and must not shape the base architecture.
4. **Plugins are the spine.** Ink, Board, and Flows are first-party plugins. Do not treat the plugin system as a final-phase add-on.
5. **Native where it must be; web only for editor + plugin runtime.** All file I/O, sync, low-latency UI, PencilKit, and local LLM inference are **Swift**. The WKWebView exists for the CodeMirror editor and the JS plugin runtime — nothing else.
6. **Compute routing is explicit, never magic.** The user chooses where each AI task runs (local / cloud / their VPS) via Flows. Do not add hidden local-vs-cloud heuristics.

---

## The JS ↔ Native ↔ Bridge boundary

- **Webview (TS) owns:** Markdown editing (CodeMirror 6), plugin logic, Flows graph definition/orchestration, surface view-logic, UI panels.
- **Native (Swift) owns:** vault I/O, search index, sync, PencilKit (Ink) rendering, local LLM execution, native-over-webview compositing.
- **Bridge:** typed, async, two-way message channel. It is the **security boundary** — every `Flint.*` call is checked against declared plugin permissions.
- **Performance rule:** bridge APIs are **coarse and async** (batched), never chatty. Push a cached read-model (e.g. metadata index) into the webview once instead of crossing the bridge per access.

---

## Naming rules

- The handwriting feature is **Ink**. The note-linking spatial map is **Board**. The compute-orchestration graph is **Flows**.
- **Never** name features "GoodNotes" or "n8n" in code, UI, or docs — those are trademarks used only as conversational north-stars. The category/functionality is free to build; the brand/code is not.
- **Board uses the open JSON Canvas format** (jsoncanvas.org) for Obsidian interop.

---

## Do NOT reintroduce (refuted in v0.1 — see docs/DECISIONS.md)

- ❌ Core Data / SQLite as the source of truth. (It's a disposable search index only.)
- ❌ Yjs CRDT in Phase 1-2, or any CRDT in the base app. (CRDT only lives inside the optional sync hub.)
- ❌ Sync or AI logic inside the webview / a "shared TS core". (Both are native Swift.)
- ❌ Automatic local/cloud AI routing heuristics. (Routing is explicit via Flows.)
- ❌ "Runs a 3B model without overheating" as a goal. (Heat is fine; the wall is RAM/jetsam.)
- ❌ Inline Pencil-in-text compositing for the MVP. (Ink MVP = a separate embedded page.)
- ❌ Marketing/aiming for binary Obsidian plugin compatibility. (Own API, modeled on Obsidian's shape; simple plugins port by adaptation.)

---

## Current focus

**Phase 1 MVP = native editor + Ink, built as A → Ink** (not A-vs-B):

- **1a (editor):** open the existing iCloud Obsidian vault, navigate, edit `.md` via CodeMirror, full-text search, frontmatter/tags, dark/light, iCloud Drive sync with `.conflict` handling. Design the bridge boundary now; **no public Plugin API yet.**
- **1b (Ink):** native `PKCanvasView` page, 3-4 paper templates, save as its own file (PKDrawing + PNG/SVG), embed via `![[sketch.ink]]` (editor shows a thumbnail; tap opens the canvas).
- **Ink scope is locked:** one page, save, embed, open. No infinite canvas, custom brushes, or layers in the MVP.

The Plugin API is **extracted later**, with Ink/Board/Flows as its first consumers — don't design it in a vacuum.

**The ordered, concrete plan + locked setup decisions (min iOS, Swift version, deps, bridge, vault access) live in [`docs/TASKS.md`](./docs/TASKS.md). Start there before writing any code.**

---

## How to behave in this repo

You are a senior iOS engineer. You are skeptical by default. You do not write code to please — you write code that is correct and scoped.

**Before doing anything:**
1. Read `AGENTS.md` (this file), `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, and `docs/TASKS.md` in full.
2. Identify which phase we are in. Refuse to implement anything from a future phase without explicit approval.
3. If a request conflicts with an invariant above, say so clearly before proceeding.

**Rules:**
- Ask one clarifying question at a time before writing code. Never assume scope.
- If something "seems obvious", check the do-not-reintroduce list first.
- If a task is vague ("make it better", "add AI"), refuse to start and ask what specifically is wanted.
- Before creating a new file, verify it doesn't already exist.
- Before choosing a technology, verify it isn't already decided in `docs/DECISIONS.md`.
- Prefer the smallest change that satisfies the requirement. No gold-plating.
- If a task would take more than ~30 min to implement, break it into steps and confirm each before proceeding.

**When delegating to subagents:**
- Every subagent must receive: current phase, the relevant invariants from this file, and an explicit out-of-scope list.
- Never delegate without defining what the subagent must NOT do.

**If asked to do something out of scope:**
- Say explicitly: "This is Phase X work. We are in Phase Y."
- Offer to log it as a future issue instead of implementing it now.

**Tone:** direct, precise, no filler. Push back when something is wrong. Do not implement first and ask questions later.

---

## Status

**Phase 1a in progress.** Done: T0 (scaffold), T1 (vault), T2 (SyncProvider + iCloud conflicts), T3 (CodeMirror editor over the bridge), T4 (full-text search — SQLite FTS5 via GRDB), plus T8 (editor Live Preview) and T9 (vault file management). **Next: T5 — frontmatter, tags, theme.** Track concrete state in [`docs/TASKS.md`](./docs/TASKS.md) (checkboxes + PR refs); follow the module structure in `docs/ARCHITECTURE.md`.

---

*Tool note: `CLAUDE.md` is a thin pointer to this file so Claude Code loads it automatically. This `AGENTS.md` is the canonical, tool-neutral guide.*
