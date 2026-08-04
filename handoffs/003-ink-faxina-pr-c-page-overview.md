# HANDOFF Flint OpenCode — Ink FAXINA PR-C: visão de páginas

> Um handoff = um commit. Execute apenas depois do PR-A estar commitado e verificado, porque este handoff depende de `InkRenderer.pagePNG(_ page: InkNotebook.Page, ...)`.

## Por quê (amarra à arquitetura)

ADR-012 promoveu o Ink MVP para um caderno multi-pagina. Sem uma visao de paginas, o usuario ate consegue navegar, mas nao tem o controle basico de caderno que torna o MVP falsificavel: ver miniaturas, pular para uma pagina, adicionar paginas e reordenar. Esse era o PR5 do handoff original e ficou faltando no pacote principal.

Esta unidade fecha a peca de UX que comprova o caderno multi-pagina sem expandir escopo para PDF, lasso, brushes customizados ou compositing inline.

## O que fazer

Criar:

- `ios/Flint/Ink/InkPageOverview.swift`

Tocar somente:

- `ios/Flint/Ink/InkScreen.swift`

Interface fixa em `InkPageOverview.swift`:

```swift
struct InkPageOverview: View {
    @Binding var pages: [InkNotebook.Page]
    let currentIndex: Int
    var onSelect: (Int) -> Void
    var onReorder: (IndexSet, Int) -> Void
    var onAdd: () -> Void
}
```

Mudanca exata:

1. Em `ios/Flint/Ink/InkPageOverview.swift`, implementar uma grade ou painel de miniaturas, uma por pagina.
2. Gerar cada miniatura com `InkRenderer.pagePNG(page, maxSize: ..., scale: ...)` e exibir via `UIImage`.
3. Marcar visualmente a pagina atual (`currentIndex`).
4. Tocar numa miniatura chama `onSelect(index)`.
5. Permitir reordenar paginas por arraste/lista/grid conforme o padrao SwiftUI mais simples e robusto; ao reordenar, chamar `onReorder(IndexSet, Int)`.
6. Incluir botao de adicionar pagina que chama `onAdd()`.
7. Em `ios/Flint/Ink/InkScreen.swift`, adicionar um botao na `controlsBar` para abrir a visao de paginas em sheet. Use um icone como `square.grid.2x2`.
8. Antes de apresentar o overview, chamar `persistDraftToCurrentPage()` para a miniatura refletir o desenho atual.
9. No `onSelect`, pular para a pagina escolhida reusando a logica existente de troca de pagina, sem perder o draft atual.
10. No `onReorder`, mover `notebook.pages`, manter `currentPageIndex` apontando para a mesma pagina por `id`, e chamar `scheduleSave()`.
11. No `onAdd`, reutilizar `addPage()`.

## Restrições

- Deps: nenhuma dependencia nova. Usar SwiftUI/UIKit/PencilKit ja disponiveis no target.
- Natureza: aditiva sobre a UX multi-pagina, com toque minimo em `InkScreen`.
- Arquivos permitidos para tocar/criar: somente `ios/Flint/Ink/InkPageOverview.swift` e `ios/Flint/Ink/InkScreen.swift`.
- Nao tocar renderer, modelo, vault, bridge, web, tokens, testes ou docs neste handoff.
- Nao mudar o formato `.ink`.
- Nao implementar PDF annotation, lasso, busca de manuscrito, brushes customizados, export SVG, nem canvas inline no editor.
- Nao quebrar a navegacao por setas, add/delete existente, seletor de papel por pagina, debounce/flush de save.
- Se overview + reorder passar claramente de ~300 linhas, pare e reporte para dividir em PR-C1 (miniaturas + pular) e PR-C2 (reordenar).
- Higiene de git: rode `git status`; use `git add ios/Flint/Ink/InkPageOverview.swift ios/Flint/Ink/InkScreen.swift`; nunca `git add -A`.
- Commit unico, mensagem sugerida: `feat: add ink page overview`.

## DoD (Definition of Done — falsificável)

1. `ios/Flint/Ink/InkPageOverview.swift` existe e declara exatamente a interface fixa `InkPageOverview`.
2. `InkScreen` apresenta o overview por um botao na barra de controles.
3. A grade/painel mostra uma miniatura para cada pagina e destaca a pagina atual.
4. Manual: criar caderno com 3 paginas, desenhar marcas diferentes, abrir overview, tocar na pagina 2; a tela abre a pagina 2.
5. Manual: reordenar paginas no overview, fechar e reabrir o caderno; a ordem persiste e a pagina atual continua apontando para a mesma pagina por `id`.
6. Manual: adicionar pagina pelo overview; a nova pagina aparece e nao quebra navegacao por setas.
7. Manual: desenhar antes de abrir o overview; a miniatura reflete o draft porque `persistDraftToCurrentPage()` roda antes da apresentacao.
8. Sem regressao manual: navegacao por setas, apagar pagina com trava de ultima pagina, seletor de papel por pagina e save continuam funcionando.
9. `make build` termina com sucesso.
10. A suite `FlintTests` passa. Comando sugerido apos `make build`/geracao do projeto:
    ```bash
    cd ios && xcodebuild -project Flint.xcodeproj -scheme Flint -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO test
    ```
11. `git diff --stat` deste handoff mostra apenas os dois arquivos permitidos e diff aproximado <= 300 linhas.

## O que isto prova e o que NÃO prova

Prova que o Ink Notebook tem a visao basica de caderno multi-pagina: miniaturas, salto, reorder, add e persistencia de ordem. Nao prova PDF annotation, compositing inline no editor, lasso, reconhecimento de formas, busca de manuscrito, nem qualidade final de GoodNotes; esses itens continuam fora do MVP atual.
