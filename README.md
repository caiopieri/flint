# Flint

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-blue)
![Status](https://img.shields.io/badge/status-early%20development-orange)
![License](https://img.shields.io/badge/license-MIT-green)

> The depth of Obsidian. The naturalness of GoodNotes. The intelligence of modern AI.

Flint is an open source note-taking app for iOS and iPadOS that brings together Markdown editing, native Apple Pencil handwriting, and local/cloud AI — in a single, privacy-first app.

## Why Flint?

No existing tool solves all three at once:

| App | Markdown | Apple Pencil | AI | Open Source | Free |
|---|---|---|---|---|---|
| Obsidian | ✅ | ❌ | plugins | ❌ | ✅ |
| GoodNotes | ❌ | ✅ | limited | ❌ | ❌ |
| Notion | partial | ❌ | ✅ | ❌ | partial |
| **Flint** | ✅ | ✅ | ✅ | ✅ | ✅ |

## Features (Roadmap)

- **Phase 1 — Markdown Editor** — Local vault, CodeMirror 6, iCloud sync, full-text search
- **Phase 2 — Handwriting Canvas** — PencilKit, paper templates, inline canvas in notes
- **Phase 3 — AI Integration** — Local models (llama.cpp/Metal) + cloud APIs (OpenAI, Anthropic)
- **Phase 4 — Plugin System + Desktop** — TypeScript plugin API, Electron app

## Privacy

Flint is privacy-first by design:

- Your notes are plain `.md` files stored **on your device** and synced through **your own iCloud** — no Flint servers in between.
- AI runs **locally by default** (on-device inference). Cloud models are opt-in and only used when you explicitly choose them.
- No tracking, no analytics, no account required.

## Stack

- **SwiftUI** — native iOS/iPadOS interface
- **PencilKit** — zero-latency handwriting with palm rejection
- **CodeMirror 6** via WKWebView — Markdown editor
- **iCloud Drive** — files-as-truth sync (an optional self-hosted replication hub comes later)
- **llama.cpp + Metal / MLX** — on-device AI inference

## Getting Started

> The project is in early conception. Contributions and feedback are welcome.

```bash
git clone https://github.com/caiopieri/flint.git
cd flint
```

More setup instructions coming as the project evolves.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT — see [LICENSE](LICENSE).

---

*Built for personal use first. If it works for the creator, it works for the community.*
