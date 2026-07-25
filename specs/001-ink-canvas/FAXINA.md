# FAXINA — Correções pós-review do Ink Notebook (fatia 001)

> **Para o executor (Codex).** Pós-review do arquiteto sobre `b22b07f` + working tree. O núcleo do caderno está bom e **fica**; isto é limpeza + a peça que faltou (overview). Leia `HANDOFF.md`, `AGENTS.md`, `docs/constitution.md`. Vale o **PRINCÍPIO VI**: interfaces fixadas; **tocar** (criar/editar/apagar) só o listado; **ler** é livre; teste não se apaga; ambiguidade → pare e pergunte.
> **Ordem:** PR-A → PR-C (C depende do renderizador limpo de A). PR-B é independente (pode ser primeiro). 3 PRs, cada um ≤ ~300 linhas.

## Contexto do review (o que já está OK — não mexer)
Modelo `InkNotebook`, I/O binário no `SyncProvider`/`VaultFileSystem`, `.ink` na árvore, `createNotebook`, `InkCanvasView` (zoom/pan via `UIScrollView` + papel), `InkScreen` multi-página (setas, add, delete com trava ≥1, papel por página, save com debounce+flush) e o embed `![[…]]` ponta a ponta (`inkEmbed.ts` registrado antes de `WikiLink`; `Bridge` com `ink.thumbnail`/`ink.open`) — tudo isso **está correto e permanece**.

---

## PR-A — Limpar a sobra da versão de página única

Restou o modelo antigo `InkDocument` e o renderizador ainda o usa; hoje só funciona porque `InkNotebook.encode` grava uma cópia disfarçada da página 0 no formato velho. É frágil — remover.

### APAGAR
- `ios/Flint/Ink/InkDocument.swift`
- `ios/FlintTests/InkDocumentTests.swift`

### TOCAR
- `ios/Flint/Ink/InkRenderer.swift` — trocar a assinatura para o modelo de caderno (mesmo corpo, lendo `page.drawingData`):
```swift
static func pagePNG(_ page: InkNotebook.Page, maxSize: CGSize, scale: CGFloat) throws -> Data
```
- `ios/Flint/Vault/VaultStore.swift` — `inkThumbnailPNG` decodifica `InkNotebook` e renderiza a página 0:
```swift
func inkThumbnailPNG(_ target: String) async -> Data? {
    guard let provider, let path = resolveInkTarget(target), let url = resolve(path) else { return nil }
    do {
        let notebook = try InkNotebook.decode(try await provider.readData(url))
        guard let first = notebook.pages.first else { return nil }
        return try InkRenderer.pagePNG(first, maxSize: CGSize(width: 320, height: 220), scale: 2)
    } catch { return nil }
}
```
- `ios/Flint/Ink/InkNotebook.swift` — **remover** o Codable customizado (o `CodingKeys`, o `init(from:)` e o `encode(to:)` que espelham a página 0). Deixar o Codable sintetizado padrão (só `pages`). Manter `init(pages:)`, `static func decode` (com o guard de `Data` vazia → default) e `encoded()`. (Pré-release, sem arquivos reais legados; não precisa de compat.)
- `ios/FlintTests/InkRendererTests.swift` — atualizar para construir `InkNotebook.Page` em vez de `InkDocument`.

### Aceite (PR-A)
- `grep -rn --include=*.swift InkDocument ios/` retorna **vazio**.
- `InkNotebookTests` + `InkRendererTests` verdes; suíte inteira verde; `make build` limpo. Diff ≤ ~300 linhas.

---

## PR-B — Reverter o scope-creep (debug-vault)

Fora do escopo da fatia, o working tree ganhou um "vault de debug" que abre sozinho e um refactor de como o vault salvo é restaurado (`ContentView.task` chamando `loadRecentsIfNeeded`/`openDebugVaultIfRequested`/`restoreSavedVaultIfNeeded`). Nada disso é da tinta.

### TOCAR
- `ios/Flint/App/ContentView.swift` e `ios/Flint/Vault/VaultStore.swift` — **reverter** ao comportamento de inicialização anterior à fatia Ink (use `git show <commit-anterior>:<arquivo>` como referência): a restauração do vault salvo volta a acontecer como antes; remover `openDebugVaultIfRequested` e o par `loadRecentsIfNeeded`/`restoreSavedVaultIfNeeded` introduzidos agora. **Não** remover nada que o Ink realmente use (o Ink não precisou tocar a inicialização).
- **Manter** `ios/Flint/App/FlintButtonStyles.swift` (`.flintIcon`): é usado pelo `InkScreen` e é razoável — só ficou fora da lista; fica.

### Aceite (PR-B)
- Comportamento de inicialização idêntico ao de antes da fatia Ink (sem abrir vault de debug). Suíte verde; `make build` limpo.
- *Se* você quiser mesmo um "abrir vault no launch" para testar, isso é uma tarefa própria, com spec — **não** entra aqui.

---

## PR-C — Visão de páginas (PR5 que faltou): miniaturas + reordenar

### CRIAR
- `ios/Flint/Ink/InkPageOverview.swift` — grade de miniaturas (uma por página, via `InkRenderer.pagePNG` → `UIImage`), com: tocar para **pular** para a página, arrastar para **reordenar**, e botão de **adicionar** página. Marcar visualmente a página atual.

### Interface FIXA
```swift
struct InkPageOverview: View {
    @Binding var pages: [InkNotebook.Page]
    let currentIndex: Int
    var onSelect: (Int) -> Void
    var onReorder: (IndexSet, Int) -> Void
    var onAdd: () -> Void
}
```

### TOCAR
- `ios/Flint/Ink/InkScreen.swift` — botão na `controlsBar` (ex.: `square.grid.2x2`) que apresenta o `InkPageOverview` (sheet). Antes de apresentar, `persistDraftToCurrentPage()`. No `onSelect`, pular para o índice (reusando a lógica de `stepPage`/troca de página). No `onReorder`, mover em `notebook.pages`, **manter `currentPageIndex` apontando para a mesma página** (case por `id`), e `scheduleSave()`. No `onAdd`, reusar `addPage()`.

### Aceite (manual)
- A grade mostra uma miniatura por página; a página atual aparece destacada.
- Tocar numa miniatura abre aquela página. Arrastar reordena; a ordem **persiste** após fechar e reabrir o caderno.
- Sem regressão na navegação por setas nem no save.

### DoD (PR-C)
- Suíte verde; `make build` limpo. Diff ≤ ~300 linhas; só os arquivos listados.

---

## Regras de escalação (PRINCÍPIO VI)
Interface fixada parece errada → pare e reporte. Precisa tocar arquivo fora da lista → pare e reporte. Teste que parece errado → pare e reporte. Ambiguidade de produto → pergunte.
