# T4 — Full-text search · Plano

> Fase 2 (FIC). Baseado em [`research.md`](./research.md). **Não implementar antes de aprovação.**

## Objetivo e critérios de aceite

Busca full-text nativa sobre o vault, índice SQLite FTS5 (GRDB) **descartável**.

Pronto quando (= DoD do T4 em `docs/TASKS.md`):
- [ ] Digitar uma query na sidebar devolve notas que casam, ranqueadas, e tocar abre a nota no editor.
- [ ] Índice construído no primeiro launch; atualizado incrementalmente quando arquivos mudam (via o watch que já alimenta `VaultStore.reload`).
- [ ] **Apagar o arquivo do índice + relançar reconstrói sem perda de dados** (prova que é descartável e nunca fonte de verdade).
- [ ] Nenhuma leitura de disco para indexar passa por fora do `SyncProvider`; o `.sqlite` mora **fora** do vault.

## Escopo

**Dentro:**
- `readForIndex(_:)` novo no `SyncProvider` (leitura plana, sem reconciliar conflito/avançar base).
- Motor `SearchIndex` (actor sobre GRDB `DatabaseQueue`, tabela FTS5) em `Search/Search.swift`.
- Ciclo de vida por-vault: `VaultStore` cria/troca/fecha o índice junto com o provider; dispara sync incremental após cada `reload()`.
- UI de busca na sidebar conforme `COMPONENTS.md §Search·T4`.
- GRDB como primeira dep SPM (`ios/project.yml`).

**Fora (explícito):**
- ❌ Tags / frontmatter / filtro por tag → **T5**. Indexar só path/título/corpo.
- ❌ Busca exposta ao webview/bridge ou a plugins. T4 é 100% nativo na sidebar; bridge intocado.
- ❌ Busca por regex, operadores booleanos avançados, fuzzy. FTS5 `MATCH` com prefixo simples.
- ❌ Realce de fundo no snippet (design pede cor no texto, não highlight).
- ❌ Refactor do `VaultStore`/sync além do necessário para pendurar o índice.

## Mudanças por arquivo

**`ios/project.yml`** — adicionar seção `packages:` com GRDB (SPM), e a dep no target `Flint`:
```yaml
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: "7.0.0"   # confirmar última major no bootstrap
targets:
  Flint:
    dependencies:
      - package: GRDB
```
`make bootstrap` regenera o `.xcodeproj`. Nunca editar o projeto gerado.

**`ios/Flint/Sync/SyncProvider.swift`** — novo método no protocolo:
```swift
/// Plain coordinated reads for the disposable search index. Unlike `read`, does
/// NOT reconcile iCloud conflicts and does NOT advance the merge base — the index
/// is derived and must observe content without perturbing sync state. Best-effort:
/// unreadable files are omitted from the result, not thrown.
func readForIndex(_ urls: [URL]) async throws -> [URL: String]
```

**`ios/Flint/Sync/iCloudDriveProvider.swift`** — implementar em um `Task.detached(.userInitiated)`: para cada URL, `try? VaultFileSystem.readNote(at:)`; juntar num dict, **sem tocar `baseCache`**, sem `resolveConflict`. (Espelha o padrão das outras impls, mas sem efeito de sync.)

**`ios/Flint/Search/Search.swift`** — o motor. `actor SearchIndex`:
- `init(vaultRoot: URL)` → abre/cria a DB em `Application Support/Flint/index/<hash-do-root>.sqlite` (NÃO no vault). `hash` = SHA-256 do path do root (estável por-vault).
- Schema: tabela FTS5 `notes(path UNINDEXED, title, body, mtime UNINDEXED)`. `PRAGMA user_version` carrega a versão do schema; se divergir ou o arquivo não abrir → dropar e recriar (rebuild). `path` é a chave (relative path).
- `func diff(current: [(path: String, mtime: Date)]) -> (toRead: [String], toDelete: [String])` — compara mtime contra o indexado.
- `func apply(upserts: [(path: String, title: String, mtime: Date, body: String)], deletes: [String])` — escreve no FTS.
- `func query(_ raw: String) -> [SearchHit]` — sanitiza a query (ver Segurança), `MATCH` com `*` de prefixo, ranqueia por `bm25(notes)`, `snippet(notes, ...)` com o termo em destaque (delimitadores que a UI mapeia para `accent-text`). Vazio/whitespace → `[]`.
- `SearchHit: Sendable { relativePath, title, snippet }`.
- GRDB `DatabaseQueue` é `Sendable` e serial; o actor garante ordenação das escritas vs queries.

**`ios/Flint/Vault/VaultStore.swift`**:
- Guardar `private var searchIndex: SearchIndex?`. Em `beginAccess`: criar `SearchIndex(vaultRoot: url)` junto com o provider; em `stopAccess`: soltar (fecha a DB) — assim trocar de vault troca o índice.
- Estado observável da busca: `var searchQuery: String = ""` e `private(set) var searchResults: [SearchHit] = []`. `isSearching: Bool { !searchQuery.trimmed.isEmpty }`.
- Após `reload()` montar a árvore: disparar um `Task` de baixa prioridade `syncIndex()` que: achata a árvore em `[(relativePath, mtime)]`, chama `index.diff`, `provider.readForIndex(staleURLs)`, `index.apply`. Coalescido como o reload já é (não duplicar watcher).
- `func runSearch()` (debounce ~200ms) → `searchResults = await index.query(searchQuery)`.
- `func openHit(_ hit: SearchHit)` → resolve `rootURL + relativePath` → `findNode` → `open(node)`. Reusa o fluxo editor existente (`selectedRelativePath` → `doc.load`).
- Título indexado = `node.name` (filename sem extensão), alinhado ao Obsidian. (H1 fica para depois, fora do T4.)

**`ios/Flint/App/VaultNavigator.swift`** (`SidebarContent`):
- Campo de busca entre o `header` e a `VaultTreeList`: `surface-raised`, `radius-md`, `border-subtle`, leading `magnifyingglass` em `text-muted`, placeholder em `text-muted` (spec §Search). Bind em `vault.searchQuery`, `.onChange` → `vault.runSearch()`.
- Quando `vault.isSearching`: trocar `VaultTreeList` por uma `SearchResultsList` (linhas título/path/snippet, termo em `accent-text`); tocar → `vault.openHit` + fechar drawer no compact. Sem resultados → linha central `text-secondary` quieta (spec). Query vazia → árvore normal.
- Reusar `.buttonStyle(.flintRow)` para as linhas, igual à árvore.

## Considerações de segurança

`docs/security-DoD.md` **não existe** no repo (anotado). App single-user, local, sem rede/auth/RLS — o checklist clássico não se aplica. O que importa aqui:
- **Sintaxe de query FTS5:** input do usuário vai num `MATCH`. Caracteres especiais do FTS5 (`"`, `*`, `:`, `-`, `(`, `)`, `^`) podem gerar *erro de sintaxe* (não injeção — a query é bind-parametrizada). Sanitizar: tokenizar o input e reescrever como termos entre aspas + `*` de prefixo (ex.: `foo bar` → `"foo"* "bar"*`). Query inválida nunca deve crashar nem vazar erro de SQL pra UI — degrada para `[]`.
- **Local do índice:** `Application Support` (app-private, fora de backup do vault e fora do iCloud do usuário). Confirma a invariante de não poluir o vault.
- **Sem PII nova:** o índice só espelha conteúdo que já está em disco; mesmo nível de sensibilidade, app-private.

## Plano de teste

`ios/FlintTests/` (segue `Diff3Tests`/`SyncBaseCacheTests`):
- **SearchIndexTests** (motor, sem UI):
  - index 3 notas → `query` casa por corpo e por título; ranking traz o match mais forte primeiro.
  - **rebuild:** popular índice, apagar o `.sqlite`, reabrir → reconstrói a partir do mesmo input sem perda (prova DoD).
  - **incremental:** `apply` upsert muda corpo → query reflete; `delete` remove → some dos resultados.
  - **diff** por mtime: arquivo inalterado não entra em `toRead`; novo/alterado entra; sumido entra em `toDelete`.
  - **sanitização:** query com `"`, `*`, parênteses não lança e devolve resultado plausível ou `[]`; query vazia/whitespace → `[]`.
  - **schema version:** abrir DB de versão antiga → rebuild limpo.
- **readForIndex** (provider): ler N URLs devolve textos; arquivo ilegível é omitido, não lança; **não** altera `SyncBaseCache` (verificar que `base(for:)` não mudou após indexar).
- UI: verificação manual nos dois simuladores (iPad overlay / iPhone push) — campo, resultados, termo em accent, abrir nota. Sem teste automatizado de SwiftUI (não há precedente no repo).

## Alternativas consideradas e descartadas

- **Busca no webview (CodeMirror search / índice em JS):** descartada — arquitetura crava índice nativo; cruzaria o bridge por-arquivo (viola coarse/async) e duplicaria leitura de vault.
- **`provider.read()` para indexar:** descartada — reconcilia conflito + avança `SyncBaseCache` N vezes; corromperia a lógica de merge do T2. Daí o `readForIndex`.
- **Índice dentro do vault (`.flint/index.sqlite`):** descartada — sincronizaria via iCloud, poluiria o vault, quebraria files-as-truth.
- **Watch por-arquivo (FSEvents/granular):** descartada para o T4 — o presenter atual é coarse; diff por mtime sobre `list()` é suficiente para vault pessoal e reusa o reload existente. Reabrir se virar gargalo.
- **`LIKE`/varredura em memória sem FTS5:** descartada — não ranqueia, não escala, e a decisão travada é FTS5/GRDB.

## Tier de implementação recomendado: **Sonnet**

Concorrência real (actor + `DatabaseQueue` + indexação em background coalescida com o sync) e a **primeira integração SPM do projeto** (GRDB no `project.yml` + sintaxe FTS5) — pela regra do FIC, sync/concorrência exige Opus/Sonnet independentemente da qualidade do plano. O plano é detalhado o bastante para não precisar de Opus, mas há julgamento no fio: ordenação escrita-vs-query no actor, sanitização da query FTS5, e o wiring do GRDB (parte mais nova e arriscada — pode pedir ajuste de versão/sintaxe no `project.yml`).

### Onde isto pode dar errado

- **GRDB no XcodeGen é território novo.** `project.yml` não tem `packages:` hoje; a versão/sintaxe pode precisar de ajuste, e `make bootstrap` tem de continuar gerando + buildando limpo. Risco concentra-se aqui — validar o build antes de escrever o motor.
- **Custo do primeiro index num vault grande.** Crawl de centenas de `.md` na primeira `reload`. Tem de rodar off-main, baixa prioridade, sem travar a abertura do vault. Se pesar, indexar em lotes/progressivo — mas não otimizar antes de medir.
- **Ordenação escrita vs query.** Se uma query rodar no meio de um `apply`, pode ver estado parcial. O actor serializa, mas há que garantir que `runSearch` não corra com `syncIndex` de forma a piscar resultados — aceitável (resultado atualiza no próximo tick), mas vale um olho.
- **Troca de vault / ciclo de vida.** `beginAccess`/`stopAccess` têm de criar e soltar o índice atômicamente; um índice preso ao vault antigo busca no lugar errado. Mapear que `stopAccess` realmente fecha a `DatabaseQueue`.
- **mtime confiável?** iCloud pode mexer em datas ao sincronizar. Se `modifiedAt` vier nil (volume não reporta), o diff trata como "sempre stale" (reindexar) — correto mas mais caro; aceitável.
```
