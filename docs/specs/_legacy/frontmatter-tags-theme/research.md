# T5 — Frontmatter, tags, theme · Research

> Fase 1 (FIC). Entender antes de planejar. Nada de código de produção aqui.

## Problema (uma frase)

Parsear o frontmatter YAML de cada `.md`, **expor as `tags`** numa lista/filtro na sidebar, e garantir que tema dark/light siga a aparência do sistema **nos dois motores** (shell nativo + CodeMirror) — sem virar fonte de verdade, sem dep nova pesada, sem quebrar o índice de busca do T4.

## Descoberta que muda o escopo

**T5.2 (tema) já está praticamente pronto.** Os dois motores leem os **mesmos tokens gerados** e seguem o sistema sozinhos:
- **Nativo:** `Tokens.swift` usa `UIColor` dinâmico (`tc.userInterfaceStyle == .light ? … : …`) — adapta automático. `FlintApp` não força `preferredColorScheme` (segue o sistema).
- **Web:** `tokens.css` define dark em `:root` e light via `@media (prefers-color-scheme: light)` + override `[data-theme]`. O tema do CodeMirror (`flintTheme`/`flintHighlight` em `editor.ts`) referencia **só `var(--flint-*)`**, então um flip de media query re-resolve as cores **ao vivo**, sem reconstruir o editor.

→ **T5.2 provavelmente reduz a verificação**, não construção: confirmar que o WKWebView troca `prefers-color-scheme` em runtime (ele propaga via trait) e checar o **flash de costura** que `COMPONENTS.md §Theme switching` explicitamente manda testar. Construir um toggle manual seria gold-plating: a task diz **"following system appearance"**, não toggle in-app.

## Arquivos e fluxo relevantes

**Parsing + metadados (nativo):**
- `ios/Flint/Vault/VaultStore.swift` — `@Observable @MainActor`. Já tem o passo de crawl `syncIndex` (linha ~284) que lê **todos os corpos** via `provider.readForIndex` (linha 297) para o índice FTS5. **Aqui o frontmatter já passa pela mão** — é o ponto natural para extrair tags na mesma varredura. Hoje: `title = filename`, `body = texto cru` (frontmatter **não** é removido — vai pro índice como corpo).
- `ios/Flint/Search/Search.swift` — `SearchIndex` (actor, FTS5). Schema `notes(path, title, body, mtime)`, `schemaVersion = 1`. Indexa o corpo cru.
- `ios/Flint/Sync/SyncProvider.swift` / `iCloudDriveProvider.swift` — `readForIndex(_ urls:)` (linha 68/70): leitura plana coordenada, **sem** reconciliar conflito nem mexer no `baseCache`. É o método certo para ler corpos sem efeito colateral de sync (decisão do T4). Reusar — nada de `FileManager` acima do provider (ADR-003/004).
- `ios/Flint/Vault/Vault.swift` — `VaultNode` (value, `Sendable`). Não carrega tags hoje.

**UI da lista/filtro de tags (nativo):**
- `ios/Flint/App/VaultNavigator.swift` — `SidebarContent` (linha 156): `header` → se `vault.isSearching` mostra `SearchResultsList`, senão `VaultTreeList`. O **mesmo molde serve para tags**: campo/estado ativo troca a árvore por uma lista filtrada. `SearchResultRow` (547) é o gabarito de row. O filtro de tags entra como um segundo "modo" do sidebar, espelhando `searchQuery`/`searchResults`.
- Estado em `VaultStore`: `searchQuery`/`searchResults`/`isSearching`/`runSearch()` (linhas 78–82, 329) são o padrão a copiar para `activeTag`/notas-filtradas.

**Renderização no editor (web):**
- `web/src/livePreview.ts` — Live Preview já renderiza `#tags` inline (conceal-and-render, T8). `editor.ts` linha 87 cita `#tags`. **O bloco de frontmatter "discreto acima do corpo"** (`COMPONENTS.md` §Frontmatter) **ainda não existe** — seria trabalho web novo.

**Design (fonte da forma visual):**
- `docs/design/COMPONENTS.md` §Frontmatter & tags (T5) e §Theme switching (T5.2); `docs/design/COLOR.md` (tag = `accent-text` âmbar). Chips: `surface-raised` fill, `radius-sm`, label `accent-text`, `ui.caption`. Filtro ativo: borda/underline `accent` 2px, **não** fill cheio.

## Padrões a seguir (já existem no repo)

- **Piggyback no crawl existente:** o `syncIndex` já varre o vault inteiro lendo corpos. Extrair tags ali (mesmo passo) evita um segundo crawl — espelha a economia do watch coalescido do T4.
- **Estado de modo no sidebar via `@Observable`:** `searchQuery`+`isSearching`+`runSearch()` é o gabarito. `activeTag` segue idêntico; `SidebarContent` ramifica como já faz para busca.
- **Metadados como mapa derivável em memória** (não no `.md`): segue a invariante "índice descartável". `UserDefaults flint.*` só para preferência leve (não para tags).
- **Parsing puro/value-type, off-main** dentro do `Task` de índice já existente (linha 277, `priority: .utility`) — concurrency Swift 6 limpa.
- **Cores/spacing via tokens** (`FlintColor`/`FlintSpace`, var(--flint-*)). Chip de tag = componente novo, mas todo derivado de token.

## Restrições

- **Invariante #2 (files-as-truth):** tags são **derivadas** do `.md`; o mapa path→tags é descartável e reconstruível. Nunca persistir tag como verdade.
- **Deps mínimas (TASKS §Locked):** GRDB é a única dep. **Não adicionar Yams.** `tags:` é YAML trivial → parser próprio mínimo (bloco `---…---` no topo; `tags:` nas formas lista `[a, b]`, bloco `- a`, ou string `a b`/`a, b`). Defensivo: YAML malformado → best-effort, nunca crash.
- **Sem `FileManager` acima do provider** (ADR-003/004): ler corpos para parsear = `readForIndex`, já existente.
- **Bridge coarse/async** (AGENTS §perf): a lista/filtro de tags do T5 é **nativa** (sidebar) → o bridge nem entra. Se um dia o editor precisar de tags, é metadata empurrada em lote, não por-acesso. Não criar chamada chatty agora.
- **Swift 6 strict concurrency:** parser e mapa de tags `Sendable`; mutação do estado observável volta pro `@MainActor`.
- **Tema = seguir o sistema** (TASKS T5.2 DoD: "toggling system appearance updates the editor too"). Escopo é seguir, não um seletor manual.
- **Segurança:** frontmatter é arquivo do próprio usuário (single-user), baixo risco; ainda assim o parser trata input como hostil (não confiar em estrutura, não estourar em entrada gigante/aninhada).

## Perguntas em aberto / riscos de interpretação

1. **Fonte das tags: só frontmatter `tags:` ou também `#tag` inline no corpo?** Obsidian agrega **as duas**. A task literal diz "Parse YAML frontmatter; surface tags", mas um vault real usa `#tag` inline. Se eu fizer só frontmatter, a lista pode sair vazia/errada num vault de verdade. **Precisa decidão** (recomendo: ambas, já que o corpo já está na mão no crawl).
2. **Renderização do bloco de frontmatter no editor (web) entra no T5?** O DoD do T5.1 ("uma nota com frontmatter mostra suas tags; lista/filtro básico") é satisfeito **só com a sidebar nativa**. O bloco discreto + chips no editor (`COMPONENTS.md`) é polish web separado. **Recomendo:** T5 = sidebar nativa (tags + lista/filtro); bloco no editor fica fora/depois, salvo se barato. Confirmar.
3. **Onde mora o mapa de tags:** memória (`[path: [Tag]]` em `VaultStore`, reconstruído no `syncIndex`) **vs** coluna/tabela no SQLite. Recomendo **memória** — evita bump de `schemaVersion` e mantém o índice FTS focado em busca. Confirmar.
4. **O índice de busca deve parar de indexar o frontmatter como corpo?** Hoje `body` cru inclui o YAML, então buscar "tags" casa o cabeçalho. Stripar frontmatter do `body` indexado é melhora natural do T5 — **mas altera comportamento do T4 e mexe em `SearchIndexTests` (14 testes)**. Decidir se entra no escopo ou fica fora.
5. **Modelo de interação do filtro:** tocar chip → filtra a lista; combina com a busca textual ou são modos exclusivos? Afeta a ramificação do `SidebarContent`.

### Onde isto pode dar errado

- **Construir T5.2 do zero quando já funciona.** O maior desperdício seria escrever plumbing de tema (push nativo→web, toggle) que o repo já resolve por tokens compartilhados — e ainda arriscar regressão. O risco inverso e real: **assumir que funciona sem testar o flip ao vivo em runtime** e o **flash de costura** que `COMPONENTS.md` manda checar. A entrega do T5.2 é majoritariamente *verificação nos dois simuladores*, não código.
- **Ambiguidade da fonte de tags (Q1).** Errar aqui faz a feature parecer quebrada num vault real (Obsidian usa `#tag` inline largamente). É a decisão mais cara de assumir errado.
- **Over-engineering contra invariantes:** puxar Yams ("é YAML, né") fura "deps mínimas"; subir `schemaVersion`/tabela de tags fura "índice descartável e enxuto". Ambos são tentações "óbvias" refutadas pelas regras.
- **Stripar frontmatter do índice (Q4)** mexe num T4 com testes verdes — se entrar, tem de vir com os `SearchIndexTests` reconciliados no mesmo PR, ou fica fora.
- **Ainda não validei** se o WKWebView reflui `prefers-color-scheme` ao trocar a aparência **com o app aberto** (vs só no boot). Se não refluir sozinho, T5.2 ganha um empurrão `[data-theme]` via bridge — pequeno, mas é trabalho que o plano precisa prever.
