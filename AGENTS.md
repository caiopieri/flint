# AGENTS.md — Flint

> Fonte da verdade portável deste repo (Codex/Cursor/Claude Code). O `CLAUDE.md` é só um shim `@AGENTS.md`.
> O núcleo universal (comportamento anti-bajulação, DoD, fluxo spec-kit, alocação de modelo) vem do
> `~/.claude/CLAUDE.md` — **não repetir aqui.** Aqui mora só o que é específico do Flint. Manter enxuto.
> Visão-norte do produto (o que o Flint é ponta a ponta): `Ideaverse/2. Pessoal/Flint.md` (fora do repo).
> *Por quê* de cada escolha: `docs/DECISIONS.md` (ADRs). Engenharia: `docs/ARCHITECTURE.md`.

## [QUENTE] O que é

App de notas **open source, local-first**, para iOS/iPadOS (depois macOS/Windows via Electron, Android). Substitui o Obsidian onde ele limita: **tinta de qualidade GoodNotes dentro de um canvas conectado, com IA agêntica nativa.** Tratar como produto pessoal sério: nasce **T1** (MVP de uso próprio) e endurece para **T2** fatia a fatia antes de lançamento público.

## [QUENTE] Stack

- **App host:** SwiftUI (iOS 26.0 mínimo, Swift 6 com strict concurrency *complete*).
- **Editor + runtime de plugins:** WKWebView carregando TypeScript (CodeMirror 6) via esquema **`flint://`** (`WKURLSchemeHandler`, nunca `file://`).
- **Tinta:** PencilKit (`PKCanvasView`) — capacidade nativa.
- **Busca:** SQLite **FTS5 via GRDB** — índice descartável, reconstruível. Nunca autoritativo.
- **Sync:** protocolo `SyncProvider`; `iCloudDriveProvider` (default). Vault aberto por document picker + **security-scoped bookmark** (ADR-011); acesso via `NSFileCoordinator`/`NSFilePresenter`.
- **IA local:** llama.cpp (Metal) base; avaliar MLX. **Core ML fora** do caminho LLM autoregressivo.
- **Tokens:** `docs/design/tokens/tokens.json` → `scripts/gen-tokens.mjs` → `Tokens.swift` + `tokens.css` (gerados, gitignored).
- **Build:** projeto gerado de `ios/project.yml` (XcodeGen); web empacotado com esbuild/npm e copiado pro bundle. Entrada: `make bootstrap`. **SwiftPM only** (sem CocoaPods/Carthage); deps mínimas.

## [QUENTE] Restrições duras (não negociar dentro de uma tarefa)

- **`.md` é a fonte da verdade**; todo DB é índice descartável e reconstruível (ADR-001). Nunca tornar o DB autoritativo.
- **Sem CRDT no app base** (ADR-002): conflito offline↔offline = 3-way merge + fallback `.conflict`. CRDT só no hub de replicação opcional futuro (ADR-003).
- **Bridge JS↔Swift é a fronteira de segurança.** APIs **coarse e async**, envelope tipado `{ id, method, payload }` (`WKScriptMessageHandlerWithReply`). Nunca chatter per-keystroke/per-file (ADR-004/005).
- **Webview só para editor + runtime de plugins.** Sync e IA são nativos Swift (ADR-004).
- **`network` negado por padrão** para plugins; grant alto e por-plugin (ADR-007). **Sem rede no target do app na fatia atual** (privacy-first).
- **Vault via security-scoped bookmark**, jamais um container iCloud próprio do Flint (ADR-011).
- **Todo acesso a disco passa por `SyncProvider`** — sem `FileManager` espalhado.
- Mudança de arquitetura é **tarefa própria com spec** — não mexer em estrutura de pastas/camadas/contratos no meio de outra tarefa.

## [QUENTE] Convenções deste projeto

- Swift 6 strict concurrency; SwiftUI (UIKit só onde o nativo exige, ex.: PencilKit). TypeScript strict no webview.
- Nenhuma cor/tamanho/tipo definido só de um lado: **tudo via `tokens.json`** (parity por construção, ADR-D03).
- Tipografia nativa: New York (leitura) / SF Pro (UI) / SF Mono (código) — zero webfont (ADR-D04).
- Ao terminar: rodar testes (`FlintTests`) + lint/type-check; cumprir o DoD do `~/.claude/CLAUDE.md`. **Nunca apagar teste sem autorização.**
- 1 tarefa = 1 PR ≤ ~300 linhas. Escopo travado do Ink no MVP: **caderno multi-página, salvar, embed, abrir** (ADR-012) — nada de canvas infinito/brushes/layers.

## [MORNO] Segurança específica

Seções de `docs/security-DoD.md` que se aplicam:

- [x] **Mobile / iOS** — entitlement `increased-memory-limit` (jetsam é o limite da IA local, ADR-009); ciclo do security-scoped bookmark (staleness/re-resolução); suspensão de geração longa em background.
- [x] **Bot / entrada de LLM** — output do modelo é **dado, nunca instrução**; validar/tipar antes de tocar o vault; ação sensível pede confirmação. Conteúdo de terceiros (web embed, nota importada, plugin) é hostil até validado.
- [ ] Banco / Postgres / Supabase — N/A (SQLite local, sem servidor multiusuário no base).
- [ ] Web / e-commerce / pagamentos — N/A.
- **Flows é superfície de segurança:** rodar workflow é rodar código → respeita o capability model e roda sandboxed (projetar quando Flows existir).
- **Motor externo / controle físico (futuro, Jarvis):** conectar um motor externo é grant alto e explícito; com controle de casa, a fronteira protege a casa **física** — conteúdo/saída de LLM nunca dispara ação física, e ação física/sensível pede confirmação fora do canal. Flint conecta-se ao Jarvis (via MCP), não o contém.

## [FRIO] Memória recuperável

- `docs/ARCHITECTURE.md` — fonte da verdade de engenharia (a fronteira bridge é a seção mais importante).
- `docs/DECISIONS.md` — ADRs com **alternativas rejeitadas** (não reintroduzir silenciosamente).
- `docs/design/` — sistema visual derivado do ícone (`COLOR`, `TYPOGRAPHY`, `INTERACTION`, `ACCESSIBILITY`, tokens).
- `ROADMAP.md` — Now/Next/Later (a camada acima da spec).
- `docs/constitution.md` — a lei do projeto; colar em `/speckit.constitution` após `specify init`.
- **Specs por fatia:** `specs/NNN-nome/{spec,plan,tasks}.md` (spec-kit). Formato antigo arquivado em `docs/specs/_legacy/`.
- `docs/TASKS.md` — tracker legado da Phase 1 (pré-spec-kit); o tracking de tarefas migra para `specs/NNN/tasks.md`.
