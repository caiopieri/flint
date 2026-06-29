# T4 — Full-text search · Research

> Fase 1 (FIC). Entender antes de planejar. Nada de código de produção aqui.

## Problema (uma frase)

Indexar path/título/corpo de cada `.md` do vault num índice **descartável** (SQLite FTS5 via GRDB), reconstruível, e expor uma busca que devolve notas ranqueadas e abre a escolhida — sem nunca virar fonte de verdade nem deixar o `.sqlite` vazar pro vault.

## Arquivos e fluxo relevantes

**Onde a busca encaixa (native-only, sem mexer no bridge):**
- `ios/Flint/Search/Search.swift` — stub vazio (`enum Search`). Aqui mora o índice FTS5 + query.
- `ios/Flint/App/VaultNavigator.swift` — shell da sidebar (`SidebarContent` → header + `VaultTreeList`). É onde um campo de busca e a lista de resultados entram. Abrir um resultado = `vault.open(node)` (linha ~408), que já dispara o editor.
- `ios/Flint/Vault/VaultStore.swift` — estado observável `@MainActor`. `open(_:)` seta `selection`; `selectedRelativePath` (linha 23) é a identidade da nota no bridge. **A busca seleciona, o editor já carrega via `doc.load` existente.** Nenhuma mudança no `Bridge.swift`/`bridge.ts` é necessária.
- `ios/Flint/Sync/SyncProvider.swift` — protocolo de acesso a disco. `list()` (árvore), `read(_:)` (texto), `watch(_:)` (mudanças externas). **Toda leitura para indexar tem de passar por aqui** (invariante ADR-003/004: nada de `FileManager` acima do provider).
- `ios/Flint/Sync/iCloudDriveProvider.swift` — implementação. `list()` → `VaultFileSystem.buildTree`. `read()` reconcilia conflito **e** chama `baseCache.update(...)` (efeito colateral, ver riscos).
- `ios/Flint/Vault/VaultFileSystem.swift` — primitivas coordenadas (`buildTree`, `readNote`, `coordinatedRead`). `VaultNode` (em `Vault.swift`) já traz `url`, `name`, `isDirectory`, `modifiedAt`, `createdAt`.
- `ios/project.yml` — projeto gerado por XcodeGen. **Não tem seção `packages:` ainda** — GRDB é a primeira dep SPM do projeto.

**Fluxo proposto:** `VaultStore.watch` → reload da árvore (já existe, debounce 150ms) → `Search` diffa árvore vs índice (mtime) → reindexa só o que mudou. Query digitada na sidebar → `Search.query(text)` → `[SearchHit]` (path, título, snippet) → tap → `vault.open(node)` → editor carrega.

## Padrões a seguir (já existem no repo)

- **Acesso a disco off-main via `Task.detached(priority:.userInitiated)`** devolvendo valor a callers `@MainActor` que só dão `await` — ver `iCloudDriveProvider` inteiro. Search deve seguir: motor próprio (actor/serial), API async.
- **Estado de UI em `@MainActor @Observable`** (`VaultStore`). Um `SearchStore`/estado de busca observável seguiria o mesmo molde; ou expor via o próprio `VaultStore`.
- **Watch coalescido**: `VaultStore.scheduleReload()` (linha 225) já junta rajadas em 1 reload com `Task.sleep(150ms)`. Indexação incremental deve pendurar no mesmo ponto, não criar um segundo watcher.
- **Caminhos vault-relativos como identidade** (`VaultStore.relativePath(of:under:)`, linha 357). O índice deve chavear por path relativo, não absoluto (URLs absolutas mudam entre devices/bookmarks).
- **Design system nativo**: cores/spacing via `FlintColor`/`FlintSpace`, `ContentUnavailableView` para vazios, `.buttonStyle(.flintRow/.flintPressable)`. Resultado de busca deve parecer uma `VaultTreeList` row.
- **Persistência leve em `UserDefaults`** com chaves `flint.*` (ver `VaultStore`). Versão do schema do índice pode ir aí.

## Restrições

- **Invariante #2 (files-as-truth):** o `.sqlite` é índice descartável e reconstruível. **DoD exige:** apagar o arquivo + relançar reconstrói sem perda. → schema versionado; rebuild total quando versão/arquivo sumir.
- **Local do índice:** **fora do vault.** Em `Application Support` (app-private), chaveado por vault (ex.: hash do path raiz). Nunca dentro da pasta do usuário — senão sincroniza via iCloud e polui o vault. Não há precedente no repo; é decisão nova a registrar.
- **Sem `FileManager` acima do `SyncProvider`** (ADR-003/004). Ler corpos para indexar tem de sair do provider — ver risco abaixo.
- **Bridge coarse/async** (AGENTS.md §perf): se algum dia a busca for exposta a plugins/web, é uma chamada batched, não por-tecla. No T4 a busca é nativa na sidebar → bridge nem entra.
- **SPM-only, GRDB (FTS5)** é decisão travada (TASKS §Locked). Adicionar via `packages:` no `project.yml`, não no `.xcodeproj` gerado. `make bootstrap`/`build` regeneram.
- **Swift 6 strict concurrency (complete):** GRDB types e o motor de busca precisam ser `Sendable`-corretos; índice atrás de um actor ou de uma `DatabaseQueue` (serial própria do GRDB).
- **Segurança:** toca disco e um DB local, mas não auth/rede/input externo não-confiável. FTS5 com queries do usuário → usar binding parametrizado / `MATCH` com query sanitizada (evitar erro de sintaxe FTS quebrar a busca), não SQL injection clássico (DB local de single-user).
- **Escopo:** T4 = índice + UI de busca. **Tags/frontmatter é T5** — não indexar/filtrar tag agora. Ink/Board/Plugins fora.

## Perguntas em aberto / riscos de interpretação

1. **Leitura para indexação vs efeito colateral do `provider.read`. ✅ RESOLVIDO.** `iCloudDriveProvider.read()` (a) tenta `resolveConflict` e (b) faz `baseCache.update(text)` — avança o ancestral de merge. Indexar o vault inteiro com `read()` dispararia reconciliação + mutação do SyncBaseCache N vezes. **Decisão:** novo método no protocolo `SyncProvider`:
   ```swift
   /// Plain coordinated read for the disposable search index. Does NOT reconcile
   /// conflicts nor advance the merge base. Best-effort: unreadable files omitted.
   func readForIndex(_ urls: [URL]) async throws -> [URL: String]
   ```
   Fica dentro do provider (honra ADR-003/004), sem efeito colateral de sync, em batch (crawl inicial + incremental usam o mesmo método). Impl = `VaultFileSystem.readNote` num `Task.detached`, sem tocar `baseCache`.
2. **Granularidade do watch.** `VaultPresenter`/`watch` só diz "algo mudou", sem qual arquivo. Incremental real = diffar `list()` (com `modifiedAt`) contra o que o índice conhece (path→mtime). Funciona, mas é um crawl de metadados a cada mudança. Aceitável para vault pessoal; confirmar que não precisa de algo mais fino.
3. **Título da nota:** primeiro `# H1` do corpo, ou nome do arquivo? Obsidian usa o filename. Definir regra (provável: filename como título, H1 opcional como campo extra).
4. **UI da busca:** campo no header da sidebar que troca a `VaultTreeList` por resultados enquanto há query? Ou uma tela/sheet separada? Afeta `SidebarContent`. Precisa bater com `docs/design/COMPONENTS.md` (não lido ainda).
5. **Tamanho do vault / custo do primeiro index.** Build no primeiro launch pode varrer centenas de `.md`. Precisa rodar off-main, idealmente incremental/progressivo, sem travar a abertura do vault.

### Onde isto pode dar errado

- **O ponto 1 é o mais caro de errar.** Se eu indexar via `provider.read()` "porque é o método público", introduzo reconciliação de conflito e mutação do `SyncBaseCache` em massa — efeito colateral silencioso que corrompe a lógica de merge do T2. Mas se eu ler com `FileManager`/`VaultFileSystem` direto "pra evitar isso", **violo a invariante de que nada acessa disco acima do provider.** A saída certa (novo método plano no protocolo) precisa de sign-off antes de codar — não dá pra assumir.
- **Local e ciclo de vida do índice por-vault.** O app troca de vault (`openRecent`, `beginAccess` recria o provider). O índice tem de ser por-vault e ser trocado/fechado junto — se eu prender um índice global, busco no vault errado depois de trocar. Ainda não mapeei como `Search` recebe o sinal de troca de vault (hoje só `VaultStore.beginAccess` sabe).
- **Não li `docs/design/COMPONENTS.md` nem `docs/ARCHITECTURE.md §Search` em detalhe** — a forma da UI de busca pode já estar especificada e divergir do que assumi (campo na sidebar).
