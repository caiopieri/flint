# Flint — Design System

The design source of truth for Flint. Read alongside [`../../AGENTS.md`](../../AGENTS.md) (product invariants) and [`../ARCHITECTURE.md`](../ARCHITECTURE.md) (the native ↔ webview boundary that this system has to span).

The whole system is **derived from the app icon** ([`../../assets/brand/flint-icon.svg`](../../assets/brand/flint-icon.svg)): a warm near-black field, a warm-gray faceted stone, and a rare amber spark. Everything below is that idea made systematic.

## Reading order

1. **[PRINCIPLES.md](./PRINCIPLES.md)** — the design philosophy and the things this app must *not* become. Read first; it decides everything else.
2. **[COLOR.md](./COLOR.md)** — the warm-neutral ramp + the amber spark accent, light/dark, with contrast proofs.
3. **[TYPOGRAPHY.md](./TYPOGRAPHY.md)** — three native, zero-bundle typefaces; the editor reading face.
4. **[COMPONENTS.md](./COMPONENTS.md)** — the Phase 1 surfaces and their specs, mapped to `docs/TASKS.md`.
5. **[INTERACTION.md](./INTERACTION.md)** — press states + haptics, and the iPhone/iPad/webview hardware limits that shape them.
6. **[ICONOGRAPHY.md](./ICONOGRAPHY.md)** — the flint/spark mark, app icon, SF Symbols policy.
7. **[ACCESSIBILITY.md](./ACCESSIBILITY.md)** — Dynamic Type, contrast, VoiceOver, reduced motion.

Design *decisions* (with rejected alternatives) live as `ADR-D*` entries in [`../DECISIONS.md`](../DECISIONS.md), same as engineering ADRs.

## tokens-as-truth

Mirrors the repo's files-as-truth discipline. There is **one** source of token values:

```
docs/design/tokens/tokens.json     ← SOURCE OF TRUTH (committed, hand-edited)
        │  scripts/gen-tokens.mjs
        ├─► ios/Flint/App/Tokens.swift   (GENERATED — gitignored)
        └─► web/src/tokens.css           (GENERATED — gitignored)
```

- **Never** hand-edit `Tokens.swift` or `tokens.css`. Edit `tokens.json` and regenerate:
  ```bash
  node scripts/gen-tokens.mjs
  ```
- The generated files are **gitignored on purpose**, exactly like the generated `Info.plist`, `*.xcodeproj`, and web bundle. They are disposable, rebuildable indexes — the JSON is canonical.
- **Dev-agent note:** wire `node scripts/gen-tokens.mjs` into `make bootstrap` (and ideally an Xcode pre-build phase) so a fresh clone has the tokens before first build. This system is design-complete but the *build wiring is intentionally left for implementation.*

This is the spine: because Flint is two render engines (SwiftUI chrome + CodeMirror in a WKWebView), one token source emitting both Swift and CSS is the only way the seam between them stays invisible.

## What lives where (open-source layout)

| Path | Committed? | Why |
|---|---|---|
| `docs/design/*.md` | ✅ yes | Public guidance for contributors. |
| `docs/design/tokens/tokens.json` | ✅ yes | The source of truth. |
| `scripts/gen-tokens.mjs` | ✅ yes | The generator. |
| `assets/brand/flint-icon.svg` | ✅ yes | The app-icon master; the app ships it. |
| `ios/Flint/App/Tokens.swift` | ❌ generated | Rebuilt from JSON; gitignored. |
| `web/src/tokens.css` | ❌ generated | Rebuilt from JSON; gitignored. |
| Exploration mockups, Figma, raster exports | ❌ keep local | Heavy/working files — keep out of git history; link from a doc if needed. |
