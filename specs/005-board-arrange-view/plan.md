# Plano — Board arrange/view MVP

## Decisões

1. Usar `.canvas` como arquivo de primeira classe no vault.
2. Manter o canvas e o gesto no webview, coerente com a fronteira de superfícies espaciais em `docs/ARCHITECTURE.md`.
3. Fazer o Swift validar e persistir um documento inteiro por operação, com escrita coarse no fim do gesto.
4. Implementar apenas cartões `file` para `.md`; nós desconhecidos são preservados e exibidos como placeholders.
5. Reutilizar `note.open`, passando caminho relativo validado, em vez de criar uma rota paralela de navegação.

## Componentes

### Swift/native

- `ios/Flint/Board/BoardDocument.swift`: modelo, codec tolerante, validação e limites.
- `ios/Flint/Board/BoardStore.swift`: load/save/create e normalização de notas, sempre via `SyncProvider`.
- `ios/Flint/Board/BoardWebView.swift`: host WKWebView que reutiliza `FlintScheme` e instala `WebBridge`.
- `ios/Flint/Vault/VaultStore.swift`: seleção/abertura de `.canvas`, criação e lista coarse de Markdown.
- `ios/Flint/Bridge/Bridge.swift`: métodos `board.load`, `board.save`, `board.notes` e uso controlado de `note.open`.

### Web

- `web/src/board.ts`: estado de viewport, renderização, hit-test e drag.
- `web/src/board.css`: tokens e layout adaptável.
- `web/src/board.html` e `web/build.mjs`: bundle separado ou modo Board sem duplicar dependências.

### Testes

- `ios/FlintTests/BoardDocumentTests.swift`: codec JSON Canvas, limites, paths, IDs e preservação.
- `ios/FlintTests/BoardStoreTests.swift`: apenas se a infraestrutura de provider fake existente suportar a fatia sem inventar um segundo backend.
- `web/src/board.test.ts`: somente lógica pura de viewport/hit-test; não testar DOM frágil como requisito principal.

## Fluxo de dados

```text
abrir .canvas
  → VaultStore resolve path relativo
  → SyncProvider.readData
  → BoardDocument.decode + validate
  → bridge reply com snapshot sanitizado
  → board.ts renderiza

fim do drag
  → board.ts envia snapshot inteiro
  → bridge valida novamente
  → VaultStore → SyncProvider.writeData
```

## Performance

- Não enviar eventos de pointermove ao Swift.
- Manter viewport em estado web local.
- Renderizar apenas nós dentro de uma margem do viewport quando a lista crescer; o limite inicial de 2.000 pode usar DOM simples se os testes manuais confirmarem fluidez.
- Debounce de save é proteção adicional, não mecanismo de consistência: `visibilitychange` e fechamento devem fazer flush.

## Ordem de implementação

1. Codec/validação e testes.
2. Store/bridge para carregar, salvar, criar e listar notas.
3. Host SwiftUI e integração com seleção do vault.
4. Runtime web de viewport, cartões e drag.
5. Estados de erro/vazio, acessibilidade e layout iPhone/iPad.
6. Testes automatizados, build e execução nos dois simuladores oficiais.

## Gate de revisão

Antes de implementar, confirmar:

- [ ] O escopo sem arestas editáveis está aceito para o MVP.
- [ ] O Board pode ser criado/aberto como `.canvas` na raiz do vault.
- [ ] Preservação de dados desconhecidos é requisito obrigatório, não nice-to-have.
- [ ] A primeira implementação de UI pode usar DOM/SVG simples dentro do webview, sem introduzir dependência de canvas externa.

### Onde isto pode dar errado

- Um host separado pode duplicar lógica do `EditorHost`; se começar a repetir bridge/scheme, extrair uma base pequena antes de adicionar comportamento.
- “Lista de notas” pode crescer além do payload seguro; manter somente caminhos/títulos e impor os limites da spec.
- Salvamento ao fechar depende de eventos corretos do SwiftUI e do webview; deve ser testado com background e troca rápida de nota.
