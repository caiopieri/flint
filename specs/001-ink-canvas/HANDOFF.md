# Handoff — Ink Notebook (fatia 001)

> **Para o executor (Codex).** Você implementa; o orquestrador (PO + arquiteto) revisa o diff.
> Antes de codar, leia: `AGENTS.md` (raiz — Codex lê nativamente), `docs/DECISIONS.md` (ADR-008, ADR-010, ADR-011) e `docs/constitution.md`.
> Fatia **T1**. Vale a constitution; em especial o **PRINCÍPIO VI**: interfaces fixadas abaixo; tocar arquivo fora da lista é violação; o DoD é a suíte passar; **nunca** apagar/editar teste sem autorização; ambiguidade → **pare e pergunte ao orquestrador**.
>
> **Autoridade do escopo:** **ADR-012** (Ink MVP promovido de "uma página" para caderno multi-página; supersede a trava de 1 página de ADR-008/010 — agora alinhado em DECISIONS, constitution e ROADMAP). "Tocar" = **criar/editar**; **ler** qualquer arquivo do repo para referência (padrões de provider, cache, testes) é livre e esperado.

---

## Discovery (resumo — já decidido)

- **Dor:** escrever à mão no Flint, como num GoodNotes — mas dentro de um app de notas conectado (o "fosso").
- **Hipótese mais arriscada:** tinta nativa **como arquivo/caderno separado** (não inline no texto) é boa o bastante; o seam de embed é evitável renderizando uma miniatura.
- **Menor teste:** um caderno de várias páginas persiste e reabre idêntico (páginas, papel por página, traços), com zoom e navegação.
- **Tier:** T1.
- **Decisão do PO (escopo):** **caderno completo no MVP** — multi-página, navegar/zoom, papel por página, miniaturas/reordenar, e embed na nota.
- **Fora de escopo (NÃO fazer):** **anotação de PDF** (próxima fatia — Ink 002); tinta inline sobre o texto do editor; lasso/seleção, reconhecimento de forma, brushes/canetas customizados além do `PKToolPicker`; busca de manuscrito; export SVG.

## O que estamos construindo

Um **caderno** de tinta. Um arquivo `.ink` no vault guarda **um caderno de N páginas**; cada página tem seu próprio desenho PencilKit e seu próprio papel (liso/pautado/grade/pontilhado). O usuário cria um caderno, escreve com o Apple Pencil (ou dedo/mouse), dá zoom/pan, vira/adiciona/remove/reordena páginas, e tudo persiste. O `.ink` aparece na árvore lateral; tocar abre o caderno. E uma nota pode embutir o caderno via `![[meucaderno.ink]]` (miniatura da 1ª página; toque abre).

### Decisões de arquitetura desta fatia (não relitigar)

1. **Formato do `.ink` = JSON `InkNotebook`** — `{ pages: [{ id, paper, drawingData }] }`. `drawingData` = bytes de `PKDrawing.dataRepresentation()`, opacos no modelo (o modelo **não** importa PencilKit, fica puro/testável). Um caderno tem **sempre ≥ 1 página**.
2. **I/O binário entra no `SyncProvider`** (ADR-003/004: nenhum `FileManager` acima dessa camada).
3. **A árvore inclui `.ink`** (além de `.md`); roteamento editor vs. caderno é por extensão. `VaultNode` **não** muda.
4. **Tela de tinta separada** (ADR-008): nada de compositing de canvas nativo sobre o webview do editor.
5. **Zoom/pan é de graça:** `PKCanvasView` **é** um `UIScrollView` — use `minimumZoomScale`/`maximumZoomScale`/`contentSize`, não reimplemente.

---

## Divisão em 6 PRs (cada um ≤ ~300 linhas) — em ordem, cada um depende do anterior

1. **PR 1 — Fundação:** modelo `InkNotebook` + I/O binário + árvore inclui `.ink`. *Testável.*
2. **PR 2 — Página + zoom:** `PKCanvasView` com zoom/pan + papel; `InkScreen` mostrando **1 página**; criar/abrir; salvar. *Manual.*
3. **PR 3 — Render PNG:** página → PNG (insumo de miniatura e embed). *Testável.*
4. **PR 4 — Multi-página:** navegar, adicionar, apagar, papel por página, indicador "n/total". *Manual.*
5. **PR 5 — Visão de páginas:** grade de miniaturas, pular para página, reordenar. *Manual.*
6. **PR 6 — Embed na nota:** `![[caderno.ink]]` vira miniatura no editor; toque abre o caderno. *Manual.* **O seam (ADR-008).**

**Revisão (orquestrador):** mínimo = uma revisão ao fim do PR 6. **Recomendo** checkpoints rápidos após o **PR 2** (1 página já usável) e o **PR 4** (multi-página funcionando) — desarmam risco antes do overview e do seam. Decisão do PO.

---

## PR 1 — Fundação (testável; portão)

### CRIAR
- `ios/Flint/Ink/InkNotebook.swift`
- `ios/FlintTests/InkNotebookTests.swift`

### TOCAR
- `ios/Flint/Sync/SyncProvider.swift` — 3 métodos no protocolo (abaixo).
- `ios/Flint/Sync/iCloudDriveProvider.swift` — implementar (siga o padrão dos métodos de texto já lá).
- `ios/Flint/Vault/VaultFileSystem.swift` — primitivos `readData`/`writeData`/`createInk`; e no `node(at:isRoot:)` relaxar o filtro de extensão para incluir `ink` (atualizar o comentário `.md` → `.md`/`.ink`).

### Interfaces FIXAS
`InkNotebook.swift`:
```swift
import Foundation

/// Formato em disco de um `.ink`: um caderno de páginas PencilKit + papel por
/// página, serializado em JSON. Tipo puro e Sendable (sem PencilKit) → testável.
struct InkNotebook: Codable, Equatable, Sendable {
    enum Paper: String, Codable, CaseIterable, Sendable { case blank, lined, grid, dotted }

    struct Page: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        var paper: Paper
        /// Bytes de `PKDrawing.dataRepresentation()`. Opacos aqui de propósito.
        var drawingData: Data
        init(id: UUID = UUID(), paper: Paper = .dotted, drawingData: Data = Data())
    }

    /// Invariante mantida pelos chamadores (UI): sempre ≥ 1 página.
    var pages: [Page]
    init(pages: [Page] = [Page()])

    /// `Data` vazia → caderno default (1 página em branco). Não lança nesse caso.
    static func decode(_ data: Data) throws -> InkNotebook
    func encoded() throws -> Data
}
```
`SyncProvider.swift` (adicionar ao protocolo):
```swift
/// Lê bytes crus de um arquivo do vault (binário). Coordenado. NÃO reconcilia
/// conflito iCloud (binário não tem merge de texto — last-writer-wins por ora).
func readData(_ url: URL) async throws -> Data
/// Grava bytes crus (coordenado, atômico).
func writeData(_ data: Data, to url: URL) async throws
/// Cria um `.ink` novo (conteúdo = `InkNotebook().encoded()`), nome não-colidente; retorna a URL.
func createInk(in directory: URL, baseName: String) async throws -> URL
```
`VaultFileSystem.swift` (espelhar `readNote`/`writeNote`/`createNote`):
```swift
static func readData(at url: URL) throws -> Data
static func writeData(_ data: Data, to url: URL) throws
static func createInk(in directory: URL, baseName: String = "Notebook") throws -> URL
```

### Aceite (TESTES — `InkNotebookTests.swift`, estilo `FlintTests/SyncBaseCacheTests.swift`)
1. Round-trip: `decode(nb.encoded()) == nb` para caderno de 1 e de várias páginas com papéis distintos e `drawingData` não-vazia.
2. `decode(Data())` → caderno com exatamente 1 página, `paper == .dotted`, sem lançar.
3. Páginas preservam ordem, `id`, `paper` e `drawingData` no round-trip.
4. I/O: em tmpdir, `writeData`→`readData` devolve os mesmos bytes; `createInk` cria `.ink` que decodifica para caderno default de 1 página.

### DoD
- [ ] Testes verdes; suíte inteira verde; `make build` limpo. Diff ≤ ~300 linhas; só os arquivos listados; nenhum teste apagado.

---

## PR 2 — Página única + zoom (manual)

### CRIAR
- `ios/Flint/Ink/InkCanvasView.swift` — `UIViewRepresentable` em volta de `PKCanvasView` (`import PencilKit` aqui). Zoom/pan via `minimumZoomScale`/`maximumZoomScale`. Papel desenhado como fundo (blank/lined/grid/dotted). `PKToolPicker` visível. `drawingPolicy = .anyInput`. Props: binding do `PKDrawing` + o `InkNotebook.Paper`.
- `ios/Flint/Ink/InkScreen.swift` — tela SwiftUI; recebe `vault: VaultStore` + `relativePath: String`. Carrega o `InkNotebook` no `.task`; nesta etapa mostra **apenas a página 0**, com seletor de papel daquela página. Salva com a disciplina do editor: debounce ao desenhar **e** flush ao sair/ocultar (espelhe `web/src/index.ts`).

### TOCAR
- `ios/Flint/Vault/VaultStore.swift` (espelhar `createNote`/`editorLoad`/`editorSave`):
```swift
func createNotebook() async                                    // provider.createInk → reload → open(node)
func notebookLoad(_ relativePath: String) async throws -> InkNotebook   // provider.readData → decode
func notebookSave(_ relativePath: String, _ notebook: InkNotebook) async throws  // encoded → writeData
```
- `ios/Flint/App/VaultNavigator.swift` — ação **"New Notebook"** junto de New Note/New Folder (`vault.createNotebook()`); e quando a seleção é `.ink` (`selection?.url.pathExtension == "ink"`), apresentar `InkScreen` em vez do editor (mesmo mecanismo de apresentação da nota).

### Aceite (manual)
- "New Notebook" cria um `.ink` na árvore; abre na tela de tinta.
- Desenhar, dar zoom/pan, sair, matar o app, reabrir: **traços e papel persistem**. (Zoom/pan funcionam, mas o nível de zoom é estado de *view* e **não** é persistido no `.ink` — by design, ADR-012.)
- Editor de `.md` sem regressão.

### DoD
- [ ] Suíte verde; `make build` limpo. Diff ≤ ~300 linhas; só os arquivos listados.

---

## PR 3 — Render de PNG (testável)

### CRIAR
- `ios/Flint/Ink/InkRenderer.swift`, `ios/FlintTests/InkRendererTests.swift`

### Interface FIXA
```swift
import PencilKit
import UIKit

enum InkRenderer {
    /// Decodifica o desenho da página e renderiza um PNG cabendo em `maxSize`
    /// (pontos) na `scale`. Página vazia → PNG transparente de `maxSize`.
    static func pagePNG(_ page: InkNotebook.Page, maxSize: CGSize, scale: CGFloat) throws -> Data
}
```
Notas: `PKDrawing(data:)` (vazio → `PKDrawing()`); `drawing.image(from: rect, scale:)` → `pngData()`; `rect` a partir de `drawing.bounds` (cair em `maxSize`).

### Aceite (TESTES)
1. `pagePNG(InkNotebook.Page(), maxSize: 256×256, scale: 2)` → `Data` começando com a assinatura PNG (`0x89 0x50 0x4E 0x47`).
2. Página com ≥1 traço (construído via `PKStroke`/`PKStrokePoint` ou fixture) → PNG válido.

### DoD
- [ ] Testes verdes; suíte verde; `make build` limpo. Diff ≤ ~300 linhas.

---

## PR 4 — Multi-página (manual)

### TOCAR (e extrair se ajudar a manter ≤300)
- `ios/Flint/Ink/InkScreen.swift` — navegação entre páginas (scroll paginado **ou** próximo/anterior), **adicionar** página (append `InkNotebook.Page()`), **apagar** a página atual (com confirmação; **bloquear apagar a última** — invariante ≥1), seletor de papel por página, indicador "n/total". Cada mutação atualiza o `InkNotebook` e salva.
- (Opcional) `ios/Flint/Ink/InkPageView.swift` — extração da view de uma página, se `InkScreen` crescer demais.

### Aceite (manual)
- Adicionar páginas; navegar entre elas; cada página tem seu papel e seus traços.
- Apagar uma página (menos a última); reabrir preserva ordem e conteúdo.

### DoD
- [ ] Suíte verde; `make build` limpo. Diff ≤ ~300 linhas; sem tocar arquivo fora da lista.

---

## PR 5 — Visão de páginas (miniaturas + reordenar) (manual)

### CRIAR
- `ios/Flint/Ink/InkPageOverview.swift` — grade/painel de miniaturas (via `InkRenderer.pagePNG`); tocar pula para a página; arrastar para **reordenar**; botão de adicionar página.

> Se overview + reordenar passar de ~300 linhas, **separe**: PR 5a (grade de miniaturas + pular para página) e PR 5b (reordenar por arraste). Escalar a divisão, não estourar o limite.

### TOCAR
- `ios/Flint/Ink/InkScreen.swift` — apresentar o overview (botão/gesto) e reagir à seleção/reordenação.

### Aceite (manual)
- Overview mostra miniatura de cada página; tocar pula; reordenar persiste após reabrir.

### DoD
- [ ] Suíte verde; `make build` limpo. Diff ≤ ~300 linhas.

---

## PR 6 — Embed na nota (manual; o seam — ADR-008)

`![[meucaderno.ink]]` numa nota renderiza a **miniatura da 1ª página** no editor (Live Preview); tocar abre o caderno na `InkScreen`. **Não** é compositing inline de canvas nativo sobre o texto (ADR-008: fica fora do MVP).

### CRIAR
- `web/src/inkEmbed.ts` — parser do node `Embed` (`![[ … ]]`), `InkEmbedWidget`, e o `ViewPlugin` que substitui o embed pela miniatura. Espelhe `livePreview.ts` (`WidgetType`, `selectionTouches` para revelar o texto cru ao editar).

### TOCAR
- `web/src/editor.ts` — registrar a extensão `Embed` **antes** de `WikiLink` em `markdown({ extensions: [...] })`; incluir `inkEmbed()` (plugin + tema) nas extensões.
- `ios/Flint/Bridge/Bridge.swift` — dois métodos no `switch`:
  - `ink.thumbnail`, payload `{ "target": String }` → `(["png": <base64>, "found": Bool], nil)`.
  - `ink.open`, payload `{ "target": String }` → efeito `vault.requestInk(target)`, retorna `(["ok": true], nil)`.
- `ios/Flint/Vault/VaultStore.swift`:
```swift
private(set) var inkRequest: String?            // path relativo que o navigator deve apresentar
func requestInk(_ target: String)               // resolve target→path; seta inkRequest
func clearInkRequest()                           // navigator chama ao fechar
func resolveInkTarget(_ target: String) -> String?   // basename OU path-relativo → path de um .ink na árvore; nil se não existe/ambíguo
func inkThumbnailPNG(_ target: String) async -> Data? // resolve + readData + decode + InkRenderer.pagePNG(pages[0])
```
- `ios/Flint/App/VaultNavigator.swift` — observar `vault.inkRequest`; quando não-nil, apresentar `InkScreen` daquele path e `clearInkRequest()` ao fechar.

### Contrato JS (`inkEmbed.ts`)
- Node `Embed`: dispara em `!` seguido de `[[`, fecha em `]]`, não cruza linha (espelhe `pairedInline`). Registrar **antes** de `WikiLink`.
- `InkEmbedWidget.toDOM`: `call<{png:string;found:boolean}>("ink.thumbnail",{target})`; se `found`, `<img src="data:image/png;base64,…">` (cursor:pointer); senão placeholder "caderno não encontrado". Clique → `call("ink.open",{target})`. `ignoreEvent()` no clique. Revelar `![[…]]` cru quando a seleção tocar o node.

### Aceite (manual)
- `![[Notebook.ink]]` (de um `.ink` existente) mostra a miniatura da 1ª página; tocar abre o caderno; editar e voltar reflete a miniatura atualizada (após reload).
- Cursor sobre o embed revela o `![[…]]` cru; sair volta à miniatura. Target inexistente → placeholder, **nunca** crash. Sem regressão no Live Preview de `.md`.

### DoD
- [ ] Suíte verde; `make build` limpo; `npm run typecheck` limpo. Diff ≤ ~300 linhas; só os arquivos listados.
- [ ] Manuais verificados. Escopo: sem compositing inline, sem PDF, sem SVG.

---

## Próxima fatia (Ink 002 — NÃO fazer agora)
**Anotação de PDF** (estilo GoodNotes): importar um PDF como páginas-fundo do caderno e anotar por cima (PDFKit + overlay PencilKit por página). Fera própria — fica para depois de o caderno fechar.

## Regras de escalação (PRINCÍPIO VI)
- Interface fixada parece errada/insuficiente → **pare e reporte**, não improvise outra.
- Precisa tocar arquivo **fora da lista** → **pare e reporte** (sinal de re-corte da fatia).
- Teste que parece errado → **pare e reporte**; não edite/apague.
- Ambiguidade de produto (papel default, comportamento de undo, gesto de navegação) → **pergunte**.
