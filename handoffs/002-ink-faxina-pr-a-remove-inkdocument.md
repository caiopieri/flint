# HANDOFF Flint OpenCode — Ink FAXINA PR-A: remover InkDocument legado

> Um handoff = um commit. Execute apenas esta unidade depois do PR-B estar commitado ou explicitamente liberado pelo Flint AGY.

## Por quê (amarra à arquitetura)

ADR-012 define o `.ink` como um caderno multi-pagina (`InkNotebook`) com paginas `{ id, paper, drawingData }`. A implementacao pos-review ainda carrega a sobra da versao de pagina unica (`InkDocument`) e o renderer pode depender dela. Isso deixa o formato real fragil: `InkNotebook.encode` pode acabar preservando compatibilidade falsa com uma pagina 0 "disfarcada", quando o produto ainda esta pre-release e nao precisa carregar esse legado.

Esta unidade remove o modelo antigo e fixa o renderer/thumbnail no modelo correto de caderno. Ela e pre-requisito para PR-C, porque a visao de paginas deve renderizar miniaturas a partir de `InkNotebook.Page`.

## O que fazer

Apagar:

- `ios/Flint/Ink/InkDocument.swift`
- `ios/FlintTests/InkDocumentTests.swift`

Tocar somente:

- `ios/Flint/Ink/InkRenderer.swift`
- `ios/Flint/Vault/VaultStore.swift`
- `ios/Flint/Ink/InkNotebook.swift`
- `ios/FlintTests/InkRendererTests.swift`

Mudanca exata:

1. Em `ios/Flint/Ink/InkRenderer.swift`, trocar a API publica do renderer para receber uma pagina de caderno:
   ```swift
   static func pagePNG(_ page: InkNotebook.Page, maxSize: CGSize, scale: CGFloat) throws -> Data
   ```
   Manter o corpo equivalente, lendo `page.drawingData` para construir o `PKDrawing`.
2. Em `ios/Flint/Vault/VaultStore.swift`, garantir que `inkThumbnailPNG(_:)` decodifica `InkNotebook`, pega `pages.first` e chama:
   ```swift
   InkRenderer.pagePNG(first, maxSize: CGSize(width: 320, height: 220), scale: 2)
   ```
   Se o target nao resolver, o provider estiver ausente, o notebook nao decodificar, ou nao houver primeira pagina, retornar `nil`.
3. Em `ios/Flint/Ink/InkNotebook.swift`, remover o Codable customizado legado:
   - remover `CodingKeys`;
   - remover `init(from:)`;
   - remover `encode(to:)`;
   - deixar o `Codable` sintetizado padrao, serializando somente `pages`.
4. Ainda em `InkNotebook.swift`, manter:
   - `init(pages:)`;
   - `static func decode(_ data: Data) throws -> InkNotebook`, incluindo o caso `Data()` -> notebook default de 1 pagina;
   - `func encoded() throws -> Data`.
5. Em `ios/FlintTests/InkRendererTests.swift`, atualizar fixtures/testes para construir `InkNotebook.Page` em vez de `InkDocument`.
6. Nao alterar a semantica do caderno: um notebook default continua com uma pagina `.dotted` e `drawingData` vazio.

## Restrições

- Deps: nenhuma dependencia nova. Usar apenas PencilKit/UIKit ja existentes onde o renderer ja usa.
- Natureza: destrutivo sobre legado pre-release (`InkDocument`) e compatibilidade falsa; seguro porque nao ha contrato publico nem arquivos reais a migrar.
- Arquivos permitidos para tocar/apagar: somente os seis listados neste handoff.
- Nao tocar `InkScreen`, `InkCanvasView`, `InkPageOverview`, bridge, web, `SyncProvider`, `VaultFileSystem` ou docs.
- Nao editar/apagar testes fora de `ios/FlintTests/InkDocumentTests.swift` (apagado porque o tipo deixa de existir) e `ios/FlintTests/InkRendererTests.swift` (atualizado para o novo tipo).
- Se qualquer teste de `InkNotebookTests` parecer errado, pare e reporte; nao adapte teste para esconder regressao de formato.
- Higiene de git: rode `git status`; use `git add ios/Flint/Ink/InkDocument.swift ios/FlintTests/InkDocumentTests.swift ios/Flint/Ink/InkRenderer.swift ios/Flint/Vault/VaultStore.swift ios/Flint/Ink/InkNotebook.swift ios/FlintTests/InkRendererTests.swift`; nunca `git add -A`.
- Commit unico, mensagem sugerida: `fix: remove legacy ink document model`.

## DoD (Definition of Done — falsificável)

1. `rg -n "InkDocument" ios --glob '*.swift'` retorna vazio.
2. `ios/Flint/Ink/InkNotebook.swift` nao contem `CodingKeys`, `init(from:)` nem `encode(to:)` customizados para compatibilidade com pagina unica.
3. `InkRenderer.pagePNG` aceita `InkNotebook.Page` e usa `drawingData` da pagina.
4. `VaultStore.inkThumbnailPNG(_:)` decodifica `InkNotebook` e renderiza a primeira pagina via `InkRenderer.pagePNG`.
5. `InkNotebookTests` e `InkRendererTests` passam dentro da suite.
6. `make build` termina com sucesso.
7. A suite `FlintTests` passa. Comando sugerido apos `make build`/geracao do projeto:
   ```bash
   cd ios && xcodebuild -project Flint.xcodeproj -scheme Flint -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO test
   ```
8. `git diff --stat` deste handoff mostra apenas os arquivos permitidos e diff aproximado <= 300 linhas.

## O que isto prova e o que NÃO prova

Prova que o formato e o renderer da Ink Notebook nao dependem mais do modelo legado de pagina unica e que thumbnails partem do `InkNotebook` real. Nao prova a UX multi-pagina, reorder, persistencia visual do overview ou o embed ponta a ponta no editor; isso fica para PR-C e verificacao manual da fatia.
