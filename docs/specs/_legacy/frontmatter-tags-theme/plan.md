# T5 — Frontmatter, tags, theme · Plan

> Fase 2 (FIC). Parte de `research.md`. **Não implementar ainda** — este doc é o gate de revisão.

## Objetivo e critérios de aceite

Extrair as tags de cada `.md` (frontmatter `tags:` **+** `#tag` inline), expô-las como lista/filtro na sidebar nativa, e confirmar que o tema dark/light segue a aparência do sistema **nos dois motores** sem flash na costura.

**Aceite (DoD do TASKS.md):**
- Abrir uma nota com frontmatter → suas tags aparecem (chips na sidebar).
- Tocar um chip → a sidebar lista só as notas com aquela tag; tocar de novo limpa.
- Trocar a aparência do sistema **com o app aberto** → shell nativo **e** editor (CodeMirror) reflua juntos, sem flash de cores trocadas na junção.
- Reabrir o app (índice FTS já persistido) → as tags continuam aparecendo (sem re-crawl do vault).

## Escopo

**Dentro:**
- Parser puro de tags (frontmatter + inline), value-type, `Sendable`, defensivo.
- Mapa `path → [tag]` em memória no `VaultStore`, alimentado no passo de índice já existente.
- UI de sidebar: faixa de chips de tags + modo "filtrado por tag" (espelha o modo de busca).
- T5.2: **verificação** do flip de tema ao vivo nos dois simuladores; código só se o flip não refluir sozinho.

**Fora (logar como follow-up, não implementar agora):**
- Bloco de frontmatter renderizado "discreto acima do corpo" no editor web (`COMPONENTS.md §Frontmatter`). O DoD é satisfeito pela sidebar nativa; chips `#tag` inline no editor já existem (T8/`livePreview.ts`).
- Stripar o frontmatter do `body` indexado pelo T4 (muda comportamento do T4 + mexe em 14 testes verdes). Não é exigido pelo DoD.
- Combinar filtro de tag **com** busca textual (são modos exclusivos — ver Decisão D5).
- Seletor manual de tema in-app / token de tema persistido. A task diz "following system appearance".
- Flow-layout multi-linha de chips; nesting visual de `#a/b`. v1 = strip horizontal rolável.

## Decisões (resolver no gate; recomendação minha entre parênteses)

- **D1 — Fonte das tags (Q1): frontmatter `tags:` + `#tag` inline (ambas).** Um vault Obsidian real usa inline largamente; só frontmatter sairia quase vazio. O corpo já está na mão no crawl, custo ~zero. É a decisão mais cara de errar.
- **D2 — Onde mora o mapa (Q3): em memória, mas reidratável do índice — não só do crawl.** Aqui **divirjo do research** (que sugeriu "só memória, reconstruído no syncIndex"): o índice FTS **persiste entre sessões**, então ao reabrir o app o diff lê **zero** arquivos e um mapa só-de-memória nasceria **vazio** mesmo com notas cheias de tags (bug de relaunch). Correção sem bump de schema, sem re-crawl, sem tocar testes do T4: o `body` já gravado no FTS **contém** o frontmatter e os `#tag`; logo reparseamos as tags a partir do `body` já indexado via um `SELECT path, body` read-only. Mapa em memória, derivado de um índice descartável — honra a invariante #2 por construção. (Alternativas D em "descartadas".)
- **D3 — Não stripar frontmatter do índice (Q4): fora.** Mantém T4 verde, PR pequeno.
- **D4 — Bloco de frontmatter no editor (Q2): fora.** Polish web separado.
- **D5 — Filtro = modo exclusivo (Q5):** tag e busca textual não combinam. Selecionar tag limpa a busca; digitar busca limpa a tag ativa. Espelha `isSearching` → `SidebarContent` ramifica em 3 estados (busca / tag / árvore).

## Mudanças por arquivo

**NOVO `ios/Flint/Vault/Frontmatter.swift`** (~60 ln)
- `enum Frontmatter { static func tags(in body: String) -> [String] }` — puro, `Sendable`, sem efeito colateral.
- Frontmatter: só se o arquivo começa com `---\n`; acha o fechamento `---`/`...` dentro de um teto de linhas; lê `tags:`/`tag:` nas 3 formas (flow `[a, b]`, bloco `- a`, escalar `a b`/`a, b`).
- Inline: varre o corpo por `#tag` **espelhando `livePreview.ts:93`** (`#` precedido de início/whitespace, seguido **sem espaço** de char de tag `[A-Za-z0-9_/-]`). Exclui `# heading`, `foo#bar`, URLs.
- Defensivo: teto de tamanho de input e de nº de tags; nunca crash; malformado → best-effort. Dedup case-insensitive, preserva a 1ª grafia, ordena alfabético.
- **Limitação conhecida (documentar no código):** não exclui `#` dentro de code fences/inline code. Aceitável p/ v1.

**`ios/Flint/Search/Search.swift`** (+~12 ln, **sem mudança de schema, sem tocar testes**)
- `func tagSource() async throws -> [(path: String, body: String)]` — `SELECT path, body FROM notes`, read-only. Reidrata o mapa no relaunch (D2).

**`ios/Flint/Vault/VaultStore.swift`** (+~55 ln)
- `private(set) var tagsByPath: [String: [String]] = [:]`; `var allTags: [String]` (únicas, ordenadas); `var activeTag: String?`.
- `var notesForActiveTag: [VaultNode]` — resolve paths→nodes via `findNode`, ordenado pelo `sortOrder` atual.
- Em `performIndexSync`, **depois** do `index.apply`: atualizar `tagsByPath` **incremental** a partir dos `texts` lidos (arquivos mudados) + remover `toDelete`. **Se `tagsByPath` estiver vazio mas o índice não** (caso relaunch, `toRead` vazio): carga única via `tagSource()` parseando cada `body`. Parse roda off-main (`nonisolated`/detached); atribuição volta ao `@MainActor`.
- `selectTag(_:)` / clear: setar `activeTag` limpa `searchQuery`; `runSearch()` com query não-vazia zera `activeTag` (D5).
- `stopAccess`: zerar `tagsByPath`/`activeTag` junto com o resto.

**`ios/Flint/App/VaultNavigator.swift`** (+~70 ln)
- `SidebarContent`: entre `searchBar` e a árvore, uma **faixa horizontal rolável de chips** (`TagChip`) quando `allTags` não vazio. Ramificação em 3: `isSearching` → resultados; `activeTag != nil` → `TagFilterList`; senão → `VaultTreeList`.
- `TagChip` (componente novo, todo via token): fill `surfaceRaised`, `radius-sm` (`FlintRadius.sm`), label `accentText`, `ui.caption`. Ativo: borda/underline `accent` 2px, **não** fill cheio (`COMPONENTS.md`/`COLOR.md`).
- `TagFilterList`: reaproveita o look das rows de arquivo da árvore (título = filename, abre no editor). Botão "x"/tocar o chip ativo limpa.

**NOVO `ios/FlintTests/FrontmatterTests.swift`** (~70 ln) — ver Plano de teste.

**T5.2 (tema) — contingência, não código por padrão:**
- O webview WKWebView adota o `traitCollection` → `prefers-color-scheme` reflui sozinho ao trocar a aparência com o app aberto; cores nativas são `UIColor` dinâmico; `FlintApp` não força `preferredColorScheme`. **Esperado: zero código.**
- **Só se** a verificação mostrar que o editor **não** reflui ao vivo: push `[data-theme]` via bridge no `EditorHost` ao detectar mudança de trait (~15 ln). Prever, não escrever às cegas.

## Considerações de segurança (`docs/security-DoD.md`)

- **Input externo é hostil:** o frontmatter é arquivo do usuário (single-user, baixo risco), mas o parser trata como hostil — teto de tamanho/aninhamento, sem crash em YAML malformado ou entrada gigante. É a única superfície de input nova.
- **Files-as-truth (#2):** tags são **derivadas**; o mapa é descartável e reconstruível do índice (também descartável). Nada de tag persistida como verdade.
- **Sem `FileManager` acima do provider (ADR-003/004):** leitura de corpos = `readForIndex`/`tagSource` (índice). Nenhum acesso a disco novo.
- **Bridge:** filtro de tags é 100% nativo → o bridge nem entra. Nada de chamada chatty nova.
- **Swift 6 strict concurrency:** parser e mapa `Sendable`; parse off-main, mutação observável no `@MainActor`.

## Plano de teste

`FrontmatterTests` (puro, espelha `SearchIndexTests` — sem UI/iCloud):
- Frontmatter forma flow `[a, b]`, bloco `- a`, escalar `a b` / `a, b` → cada uma extrai as tags.
- `#tag` inline coletada; `# heading`, `word#frag`, URL `http://x#y` **excluídos**.
- Frontmatter + inline → dedupe case-insensitive (`#Work` + `work` = 1), grafia preservada, ordem alfabética.
- Sem frontmatter / frontmatter malformado / sem fechamento → best-effort, sem crash, sem lixo.
- Input gigante / muitas tags → retorna dentro do teto, sem crash.
- Vazio → `[]`.

Verificação manual (dois simuladores — iPad + iPhone, ver memória `show-on-both-simulators`):
- Nota com tags → chips aparecem; tocar filtra; tocar de novo limpa; busca e tag não se misturam.
- **Relaunch** com índice já populado → tags ainda aparecem (prova D2; sem re-crawl).
- **T5.2:** trocar Appearance no Settings do simulador com o app aberto → shell + editor flipam juntos; observar a **costura** (sidebar↔editor) por flash de cor trocada.

## Alternativas consideradas e descartadas

- **Mapa só em memória reconstruído no crawl (research #3):** quebra no relaunch (índice persiste, diff lê 0 arquivos → mapa vazio). Descartado por D2.
- **Coluna/tabela `tags` no SQLite + bump de schemaVersion:** funciona e é honesto (índice descartável), mas toca o T4 e os 14 testes verdes e estoura o diff. D2 entrega o mesmo sem tocar em nada disso.
- **Re-crawl completo do vault no open só p/ tags:** reintroduz exatamente o custo de I/O que o T4 eliminou. Descartado — D2 lê do índice, não do disco.
- **Yams para o frontmatter:** fura "deps mínimas" (TASKS §Locked). `tags:` é YAML trivial → parser próprio.
- **Bloco de frontmatter no editor agora:** escopo web extra não exigido pelo DoD. Follow-up.

## Tier de implementação recomendado: **Sonnet**

Toda decisão está neste plano e o parser tem testes que cobrem a verificação — mas resta **julgamento de SwiftUI** na sidebar e a **verificação visual do flip de tema** (a parte do T5.2 que os testes não cobrem). Não é concorrência/sync nem integração externa cabeluda (é local, single-user, índice derivado), então **Opus não é obrigatório**. Não é "barato" porque a UI e o flip ao vivo exigem olho humano no simulador, não só rede de testes. → **Sonnet**, com a verificação nos dois simuladores como gate.

**Sugestão de divisão (PR ≤300 ln):** PR1 = T5.1 (parser + mapa + sidebar, ~250 ln). PR2 = T5.2 (verificação; código só se o flip falhar). Já são subtasks separadas no TASKS.md.

### Onde isto pode dar errado

- **Relaunch (D2) é o risco silencioso #1.** Se a reidratação via `tagSource()` não disparar (ex.: `tagsByPath` vazio mas a carga única não roda porque `performIndexSync` retornou cedo num guard), as tags somem após reabrir e ninguém percebe nos testes unitários. Por isso o relaunch é item explícito da verificação manual.
- **`prefers-color-scheme` pode não refluir ao vivo.** Ainda não validei em runtime (só no boot). Se não refluir, o T5.2 ganha o push `[data-theme]` previsto — pequeno, mas é trabalho não-zero. Não declarar T5.2 pronto sem ver o flip ao vivo.
- **Flash na costura.** Mesmo com tokens compartilhados, nativo e webview podem repintar em frames diferentes → flash de meio-segundo na junção sidebar↔editor. `COMPONENTS.md` manda testar exatamente isso; pode exigir um detalhe de timing.
- **Inline `#tag` em code blocks** vira tag falsa (ex.: `#define`, `#include`). Limitação aceita; se o vault do autor for cheio de código, a lista de tags fica poluída e vira pedido de ajuste.
- **Diff por mtime herda a tolerância de 0.5s do T4:** uma tag editada sem mudar mtime o bastante não reindexação → tag stale. Mesma staleness da busca; consistente, mas é uma suposição herdada.
- **Custo do parse na carga única:** reidratar de `tagSource()` lê todos os `body` do FTS na memória de uma vez. Para vault gigante é um pico transitório; mitigado por rodar off-main e descartar os corpos após o parse.
