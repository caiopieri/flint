# HANDOFF Flint OpenCode — Ink FAXINA PR-B: reverter debug-vault

> Um handoff = um commit. Execute apenas esta unidade. Se algo estiver ambiguo, pare e pergunte ao Flint AGY.

## Por quê (amarra à arquitetura)

A fatia Ink Notebook deve limpar o que ficou fora do escopo sem alterar o nucleo do caderno. O working tree ganhou um "vault de debug" que abre sozinho e um refactor de inicializacao do vault salvo (`ContentView.task` chamando `loadRecentsIfNeeded`, `openDebugVaultIfRequested` e `restoreSavedVaultIfNeeded`). Isso nao faz parte da tinta, altera comportamento de launch e enfraquece a disciplina de escopo do Flint.

Esta unidade remove esse scope-creep e restaura o comportamento de inicializacao anterior a fatia Ink, preservando apenas o que a Ink realmente usa.

## O que fazer

Tocar somente:

- `ios/Flint/App/ContentView.swift`
- `ios/Flint/Vault/VaultStore.swift`

Mudanca exata:

1. Em `ios/Flint/App/ContentView.swift`, reverter a inicializacao ao comportamento anterior a fatia Ink. Use `git show b22b07f^:ios/Flint/App/ContentView.swift` como referencia do estado pre-Ink.
2. Remover qualquer chamada de launch relacionada a debug-vault ou ao refactor fora de escopo:
   - `loadRecentsIfNeeded`
   - `openDebugVaultIfRequested`
   - `restoreSavedVaultIfNeeded`
3. Em `ios/Flint/Vault/VaultStore.swift`, remover as implementacoes auxiliares introduzidas para esse fluxo de debug/restauracao fora de escopo, mantendo a restauracao do vault salvo como ela era antes da fatia Ink. Use `git show b22b07f^:ios/Flint/Vault/VaultStore.swift` como referencia, mas nao reverta partes que a Ink Notebook usa.
4. Manter `ios/Flint/App/FlintButtonStyles.swift` e o estilo `.flintIcon`. Ele e usado por `InkScreen` e fica fora deste handoff.
5. Nao remover nem alterar APIs reais da Ink Notebook (`createNotebook`, `notebookLoad`, `notebookSave`, `requestInk`, `clearInkRequest`, `resolveInkTarget`, `inkThumbnailPNG`) salvo se alguma delas tiver sido acidentalmente acoplada ao debug-vault. Se isso acontecer, pare e reporte antes de mexer.

## Restrições

- Deps: nenhuma dependencia nova. Swift stdlib/Foundation/SwiftUI existentes apenas.
- Natureza: destrutivo apenas sobre o scope-creep de debug-vault; nao e uma limpeza geral.
- Arquivos permitidos para tocar: somente `ios/Flint/App/ContentView.swift` e `ios/Flint/Vault/VaultStore.swift`.
- Nao tocar testes neste handoff.
- Nao tocar `InkScreen`, `InkCanvasView`, `InkNotebook`, `InkRenderer`, bridge, web ou design tokens.
- Nao implementar um novo modo de debug-vault. Se for necessario para desenvolvimento, isso vira tarefa propria com spec.
- Higiene de git: rode `git status` antes de editar; adicione arquivos especificos com `git add ios/Flint/App/ContentView.swift ios/Flint/Vault/VaultStore.swift`; nunca `git add -A`.
- Se arquivo tracked aparecer como deletado por acidente, nao commite a delecao; investigue e restaure de forma especifica.
- Commit unico, mensagem sugerida: `fix: remove ink debug vault scope creep`.

## DoD (Definition of Done — falsificável)

1. `rg -n "openDebugVaultIfRequested|loadRecentsIfNeeded|restoreSavedVaultIfNeeded" ios/Flint/App/ContentView.swift ios/Flint/Vault/VaultStore.swift` nao encontra ocorrencias.
2. O comportamento de inicializacao volta ao estado anterior a fatia Ink: o app nao abre vault de debug automaticamente no launch.
3. As APIs da Ink Notebook continuam presentes em `VaultStore`: `createNotebook`, `notebookLoad`, `notebookSave`, `requestInk`, `clearInkRequest`, `resolveInkTarget`, `inkThumbnailPNG`.
4. `make build` termina com sucesso.
5. A suite `FlintTests` passa. Comando sugerido apos `make build`/geracao do projeto:
   ```bash
   cd ios && xcodebuild -project Flint.xcodeproj -scheme Flint -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO test
   ```
6. `git diff --stat` deste handoff mostra apenas os dois arquivos permitidos e diff aproximado <= 300 linhas.

## O que isto prova e o que NÃO prova

Prova que a fatia Ink nao mudou o comportamento de inicializacao por meio de um vault de debug fora de escopo e que o app ainda compila/testa depois da reversao. Nao prova a corretude do caderno Ink, do renderer, do embed ou da visao de paginas; esses ficam para PR-A e PR-C.
