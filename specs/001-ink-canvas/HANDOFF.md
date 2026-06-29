# Handoff — Ink Canvas MVP (fatia 001)

> **Para o executor (Codex).** Você implementa; o orquestrador (PO + arquiteto) revisa o diff.
> Antes de codar, leia: `AGENTS.md` (raiz — Codex lê nativamente), `docs/DECISIONS.md` (ADR-008, ADR-010, ADR-011) e `docs/constitution.md`.
> Esta é uma fatia **T1**. Vale a constitution inteira; em especial o **PRINCÍPIO VI** (interfaces fixadas abaixo; tocar fora da lista de arquivos é violação; o DoD é a suíte passar; **nunca** apagar/editar teste sem autorização; ambiguidade → **pare e pergunte ao orquestrador**, não decida).

---

## Discovery (resumo — já decidido nas ADRs)

- **Dor:** hoje não dá pra escrever à mão no Flint. A tinta é o diferenciador (o "fosso": tinta de qualidade GoodNotes dentro de um app de notas conectado).
- **Hipótese mais arriscada:** tinta nativa **como página/arquivo separado** (não inline no texto) é boa o bastante e o seam de embed é evitável. Esta fatia ataca exatamente isso, fazendo o caminho mais fino: criar → desenhar → salvar → reabrir e ver os traços.
- **Menor teste:** um desenho persiste e reabre idêntico (PKDrawing round-trip), e o arquivo `.ink` aparece e abre pela árvore do vault.
- **Tier:** T1 (uso próprio; segurança mínima + teste no caminho crítico).
- **Fora de escopo (NÃO fazer nesta fatia):** embed `![[sketch.ink]]` em nota e thumbnail no editor (fatia 002); tinta inline sobre o texto; canvas infinito; brushes/layers customizados; merge de conflito de arquivo binário; export PNG/SVG.

## O que estamos construindo

Uma tela de tinta autônoma. Um arquivo `.ink` no vault guarda **um** desenho PencilKit + o template de papel. O usuário cria um desenho, escreve com o Apple Pencil (ou dedo/mouse), e ao sair o desenho é salvo no arquivo; reabrir restaura os traços. O `.ink` aparece na árvore lateral junto das notas; tocar nele abre a tela de tinta (em vez do editor).

### Decisões de arquitetura desta fatia (não relitigar)

1. **Formato do `.ink` = JSON** (um wrapper pequeno: `{ paper, drawingData }`), não PKDrawing cru. Mantém o template de papel junto, é um documento testável e puro, e é à prova de futuro. `drawingData` são os bytes de `PKDrawing.dataRepresentation()`, opacos no modelo (o modelo **não** importa PencilKit).
2. **I/O binário entra no `SyncProvider`** (ADR-003/004: nenhum `FileManager` acima dessa camada). Adicionar `readData`/`writeData`/`createInk` — espelhando os métodos de texto existentes.
3. **A árvore passa a incluir `.ink`** (além de `.md`). O roteamento (editor vs. tela de tinta) é por extensão do arquivo selecionado — `VaultNode` **não** ganha campo novo.
4. **A tela de tinta é separada** (ADR-008): nada de compositing de canvas nativo sobre o webview do editor nesta fatia.

---

## Divisão em 4 PRs (cada um ≤ ~300 linhas) — esta é a fatia que fecha o "Ink MVP" do roadmap

A fatia completa do Ink MVP (ADR-008/010: *uma página, salvar, embed, abrir*) é dividida em 4 PRs, **em ordem** — cada um depende do anterior:

1. **PR 1 — Fundação** (documento `.ink` + I/O binário + árvore). Testável.
2. **PR 2 — Tela de tinta** (canvas PencilKit + criar/abrir + papéis). Manual.
3. **PR 3 — Render PNG** (PKDrawing → PNG; alimenta o thumbnail). Testável.
4. **PR 4 — Embed na nota** (`![[sketch.ink]]` vira thumbnail; toque abre o canvas). Manual. **É o seam mais delicado** (ADR-008).

**Pontos de revisão (orquestrador):** o mínimo é **uma revisão ao fim do PR 4** (o MVP inteiro). **Recomendo** um checkpoint rápido **após o PR 2** — é o marco "já dá pra usar" e desarma o risco do seam (PR 3-4). Decisão do PO. Em qualquer drift de interface, o executor **para e reporta** (ver Regras de escalação).

---

## PR 1 — Fundação (testável; este é o portão)

### Arquivos a CRIAR
- `ios/Flint/Ink/InkDocument.swift`
- `ios/FlintTests/InkDocumentTests.swift`

### Arquivos a TOCAR
- `ios/Flint/Sync/SyncProvider.swift` — adicionar 3 métodos ao protocolo.
- `ios/Flint/Sync/iCloudDriveProvider.swift` — implementar os 3 métodos (siga o padrão dos métodos de texto já existentes lá).
- `ios/Flint/Vault/VaultFileSystem.swift` — adicionar os primitivos coordenados `readData`/`writeData`/`createInk`.
- `ios/Flint/Vault/VaultFileSystem.swift` — no `node(at:isRoot:)`, relaxar o filtro de extensão para incluir `ink`; atualizar o comentário do `buildTree` (`.md` → `.md`/`.ink`).

### Interfaces FIXAS (assinaturas exatas — não redesenhar)

`InkDocument.swift`:
```swift
import Foundation

/// Formato em disco de um arquivo `.ink`: um wrapper JSON em volta de um desenho
/// PencilKit + o template de papel. Um arquivo = um desenho (escopo travado).
/// Tipo puro e Sendable — sem dependência de PencilKit, para ser unit-testável.
struct InkDocument: Codable, Equatable, Sendable {
    enum Paper: String, Codable, CaseIterable, Sendable {
        case blank, lined, grid, dotted
    }

    var paper: Paper
    /// Bytes de `PKDrawing.dataRepresentation()`. Opacos aqui de propósito.
    var drawingData: Data

    init(paper: Paper = .dotted, drawingData: Data = Data())

    /// Decodifica de bytes de arquivo. `Data` vazia → documento default (arquivo recém-criado).
    static func decode(_ data: Data) throws -> InkDocument

    /// Serializa para gravar em disco.
    func encoded() throws -> Data
}
```

`SyncProvider.swift` (adicionar ao protocolo):
```swift
/// Lê os bytes crus de um arquivo do vault (binário: `.ink`, anexos futuros).
/// Coordenado. NÃO reconcilia conflito do iCloud (binário não tem merge de texto).
func readData(_ url: URL) async throws -> Data

/// Grava bytes crus (coordenado, atômico).
func writeData(_ data: Data, to url: URL) async throws

/// Cria um novo arquivo `.ink` vazio (conteúdo = `InkDocument().encoded()`),
/// com nome não-colidente; retorna a URL criada.
func createInk(in directory: URL, baseName: String) async throws -> URL
```

`VaultFileSystem.swift` (novos primitivos, espelhando `readNote`/`writeNote`/`createNote`):
```swift
static func readData(at url: URL) throws -> Data
static func writeData(_ data: Data, to url: URL) throws
static func createInk(in directory: URL, baseName: String = "Drawing") throws -> URL
```

### Critérios de aceite (TESTES — escritos por você, são o DoD)
Em `InkDocumentTests.swift` (use `XCTest`; siga o estilo de `FlintTests/SyncBaseCacheTests.swift`):
1. **Round-trip:** `InkDocument.decode(doc.encoded()) == doc` para um doc com `drawingData` não-vazia e cada `Paper`.
2. **Vazio:** `InkDocument.decode(Data())` retorna o documento default (`paper == .dotted`, `drawingData` vazia), sem lançar.
3. **Preserva paper e bytes:** mudar `paper` e `drawingData` sobrevive ao round-trip.
4. **(I/O) round-trip de dados via provider/FS:** num diretório temporário, `writeData` seguido de `readData` devolve os mesmos bytes; `createInk` cria um arquivo `.ink` cujo conteúdo decodifica para um `InkDocument` default. (Espelhe o setup de tmpdir de `SearchIndexTests`/`SyncBaseCacheTests`.)

### DoD do PR 1
- [ ] Os 4 testes acima passando; toda a suíte `FlintTests` verde.
- [ ] Type-check / build limpos (`make build`).
- [ ] Diff ≤ ~300 linhas; nenhum arquivo fora da lista acima tocado.
- [ ] Nenhum teste existente apagado/desabilitado.

---

## PR 2 — UI (depende do PR 1)

### Arquivos a CRIAR
- `ios/Flint/Ink/InkCanvasView.swift` — `UIViewRepresentable` em volta de `PKCanvasView` + `PKToolPicker`. `import PencilKit` mora aqui. Props: binding para o `PKDrawing` e o `InkDocument.Paper` (renderizado como fundo: blank/lined/grid/dotted). Aceita Pencil, dedo e mouse (`drawingPolicy = .anyInput`).
- `ios/Flint/Ink/InkScreen.swift` — tela SwiftUI. Recebe `vault: VaultStore` + `relativePath: String`. Carrega o `InkDocument` no `.task`, hospeda `InkCanvasView`, e **salva com a mesma disciplina do editor**: debounce ao desenhar **e** flush ao sair/ocultar (espelhe `web/src/index.ts` / o flush do editor — nunca perder traço). Inclui um seletor dos 4 papéis que atualiza o doc e re-salva.

### Arquivos a TOCAR
- `ios/Flint/Vault/VaultStore.swift` — adicionar (espelhando `createNote`/`editorLoad`/`editorSave`):
```swift
func createDrawing() async                                   // provider.createInk → reload → open(node)
func inkLoad(_ relativePath: String) async throws -> InkDocument   // provider.readData → InkDocument.decode
func inkSave(_ relativePath: String, _ doc: InkDocument) async throws  // doc.encoded → provider.writeData
```
- `ios/Flint/App/VaultNavigator.swift` — duas mudanças, seguindo os padrões que já existem nesse arquivo:
  1. Uma ação **"New Drawing"** junto das ações New Note / New Folder, chamando `vault.createDrawing()`.
  2. Quando a seleção é um nó `.ink` (`selection?.url.pathExtension == "ink"`), apresentar `InkScreen` em vez do editor (mesmo mecanismo de apresentação que o editor já usa para uma nota selecionada).

### Critérios de aceite (manual — UI PencilKit não é unit-testável)
- Criar um desenho ("New Drawing"): aparece na árvore como arquivo `.ink`.
- Desenhar, sair da tela, matar o app, reabrir o `.ink`: os traços persistem idênticos.
- Trocar o papel (ex.: dotted → grid) persiste após reabrir.
- O editor de Markdown continua funcionando normalmente para `.md` (nenhuma regressão).

### DoD do PR 2
- [ ] Suíte `FlintTests` continua verde; `make build` limpo.
- [ ] Os 4 itens manuais acima verificados em device/simulador.
- [ ] Diff ≤ ~300 linhas; nenhum arquivo fora da lista tocado.
- [ ] Escopo: nada de embed/inline/infinito/brushes/export (é fatia 002+).

---

## PR 3 — Render de PNG (testável)

Renderiza um desenho para PNG — insumo do thumbnail do embed (PR 4) e da representação portátil (ADR-008). **SVG fica fora do MVP** (futuro).

### Arquivos a CRIAR
- `ios/Flint/Ink/InkRenderer.swift`
- `ios/FlintTests/InkRendererTests.swift`

### Interface FIXA
```swift
import PencilKit
import UIKit

/// Renderiza tinta para bitmap. PencilKit mora aqui (InkDocument continua puro).
enum InkRenderer {
    /// Decodifica o desenho do documento e renderiza um PNG cabendo em `maxSize`
    /// (pontos) na `scale` dada. Desenho vazio → PNG transparente de `maxSize`.
    static func thumbnailPNG(for doc: InkDocument, maxSize: CGSize, scale: CGFloat) throws -> Data
}
```
Notas: decodificar via `PKDrawing(data:)` (Data vazia → `PKDrawing()`); renderizar via `drawing.image(from: rect, scale:)` → `pngData()`. Calcular `rect` a partir de `drawing.bounds` (cair em `maxSize` quando o desenho for vazio/minúsculo).

### Critérios de aceite (TESTES)
1. `thumbnailPNG(for: InkDocument(), maxSize: 256×256, scale: 2)` retorna `Data` não-vazia começando com a assinatura PNG (`0x89 0x50 0x4E 0x47`).
2. Um `InkDocument` cujo `drawingData` veio de um `PKDrawing` com ao menos um traço também produz PNG válido (construa o traço com `PKStroke`/`PKStrokePoint` no teste, ou carregue um fixture pequeno).

### DoD do PR 3
- [ ] Testes acima verdes; suíte inteira verde; `make build` limpo. Diff ≤ ~300 linhas; só os arquivos listados.

---

## PR 4 — Embed na nota (manual; o seam — ADR-008)

`![[algumdesenho.ink]]` numa nota renderiza um **thumbnail** no editor (Live Preview); tocar abre a tela de tinta. **Não é** compositing inline de canvas nativo sobre o texto — é uma imagem + um toque que apresenta a `InkScreen`. Esse desvio é deliberado (ADR-008: o compositing inline é o seam mais difícil do projeto e fica fora do MVP).

### Arquivos a CRIAR
- `web/src/inkEmbed.ts` — o parser do node `Embed` (`![[ … ]]`), o `InkEmbedWidget` e o `ViewPlugin` que substitui o embed pelo thumbnail. Espelhe os padrões de `livePreview.ts` (WidgetType, `selectionTouches` para revelar o texto cru ao editar).

### Arquivos a TOCAR
- `web/src/editor.ts` — registrar a extensão de markdown do `Embed` **antes** de `WikiLink` em `markdown({ extensions: [...] })`, e incluir o `inkEmbed()` (plugin + tema) na lista de extensões.
- `ios/Flint/Bridge/Bridge.swift` — dois métodos novos no `switch`:
  - `ink.thumbnail`, payload `{ "target": String }` → `(["png": <base64 String>, "found": Bool], nil)`.
  - `ink.open`, payload `{ "target": String }` → efeito colateral `vault.requestInk(target)`, retorna `(["ok": true], nil)`.
- `ios/Flint/Vault/VaultStore.swift` — adicionar:
```swift
private(set) var inkRequest: String?            // path relativo que o navigator deve apresentar
func requestInk(_ target: String)               // resolve target→path; seta inkRequest (ou erro se não achar)
func clearInkRequest()                           // navigator chama ao fechar a tela
func resolveInkTarget(_ target: String) -> String?   // basename OU path-relativo → path relativo de um .ink na árvore; nil se não existe/ambíguo
func inkThumbnailPNG(_ target: String) async -> Data? // resolve + readData + InkRenderer.thumbnailPNG (nil se não achar)
```
- `ios/Flint/App/VaultNavigator.swift` — observar `vault.inkRequest`; quando não-nil, apresentar `InkScreen` para aquele path (e `clearInkRequest()` ao fechar). Reusa a `InkScreen` do PR 2.

### Contrato JS (`inkEmbed.ts`)
- Node `Embed`: dispara em `!` seguido de `[[`, fecha em `]]`, não cruza linha (espelhe `pairedInline`). Registrar **antes** de `WikiLink`.
- `InkEmbedWidget`: no `toDOM`, chama `call<{png:string;found:boolean}>("ink.thumbnail",{target})`; se `found`, mostra `<img src="data:image/png;base64,…">` (com `cursor:pointer`); senão um placeholder "desenho não encontrado". Clique → `call("ink.open",{target})`. `ignoreEvent()` para o clique não virar edição. Revelar o texto cru `![[…]]` quando a seleção tocar o node (como o resto do Live Preview).

### Critérios de aceite (manual)
- Numa nota, digitar `![[Drawing.ink]]` (nome de um `.ink` que existe) mostra o thumbnail do desenho.
- Tocar no thumbnail abre a tela de tinta daquele arquivo; editar e voltar reflete o desenho atualizado (após reabrir/reload).
- Posicionar o cursor sobre o embed revela o `![[…]]` cru para edição; sair volta ao thumbnail.
- Target inexistente → placeholder, **nunca** crash. Nenhuma regressão no Live Preview de `.md`.

### DoD do PR 4
- [ ] Suíte verde; `make build` limpo; `npm run typecheck` limpo (web). Diff ≤ ~300 linhas; só os arquivos listados.
- [ ] Itens manuais verificados em device/simulador.
- [ ] Escopo: sem compositing inline, sem SVG, sem export externo.

---

## Regras de escalação (PRINCÍPIO VI)
- Se alguma **interface fixada** acima parecer errada ou insuficiente, **pare e reporte** ao orquestrador — não improvise outra.
- Se algo exigir tocar um arquivo **fora da lista**, **pare e reporte** (provavelmente é sinal de que a fatia precisa ser re-cortada).
- Teste que parece errado: **pare e reporte**; não edite/apague.
- Ambiguidade de produto (ex.: qual papel default, comportamento de undo): **pergunte** — não decida sozinho.
