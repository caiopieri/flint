# Tarefas — Board arrange/view MVP

Tier do executor: médio após a revisão do plano. O executor não deve alterar contratos fora dos arquivos listados sem escalar.

## P0 — modelo e segurança

- [x] Criar `BoardDocument.swift` com nós/arestas JSON Canvas e armazenamento de campos desconhecidos.
- [x] Implementar `decode`, `encode` e `validate` com limites de tamanho, geometria e path.
- [x] Escrever testes para JSON válido, JSON inválido, nó desconhecido, path traversal, duplicata e limite de nós.

## P0 — vault e bridge

- [x] Adicionar operações de Board ao `VaultStore` usando apenas `SyncProvider`.
- [x] Adicionar `.canvas` ao tree sem fazê-lo virar nota Markdown.
- [x] Adicionar `board.load`, `board.save` e `board.notes` ao `WebBridge` com payloads validados.
- [x] Cobrir erro de arquivo ausente e save inválido pelo caminho de erro da bridge.

## P0 — superfície

- [x] Criar `BoardWebView`/`BoardScreen` com título, adicionar nota, zoom e estado vazio.
- [x] Criar runtime web do Board com viewport, cartões `file`, pan, zoom e drag.
- [x] Enviar snapshot somente ao fim de drag e fazer flush ao esconder a página.
- [x] Abrir nota ao tocar cartão usando método nativo existente.
- [x] Aplicar layout/tokenização e labels básicos de acessibilidade para iPhone 16 e iPad A16.

## Gate de validação

- [x] `xcodebuild test` no iPhone 16 oficial.
- [x] `xcodebuild test` no iPad A16 oficial.
- [x] `npm --prefix web run typecheck`.
- [x] `npm --prefix web run build` e `git diff --check`.
- [ ] Aceite manual: criar, adicionar, mover, fechar/reabrir e abrir uma nota.

### Onde isto pode dar errado

- Não começar a UI antes de os testes do codec passarem; sem isso o risco principal de interoperabilidade fica invisível.
- Não usar `FileManager` diretamente em Board para “simplificar” o primeiro protótipo.
- Não considerar build verde como aceite de gesto, zoom ou persistência real no simulador.
