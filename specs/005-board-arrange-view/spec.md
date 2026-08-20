# Board — arrange/view MVP

Status: implementação em andamento; revisão de escopo aprovada  
Tier: T1  
Executor: premium para arquitetura/UI; médio para a implementação depois da aprovação

## Problema

O Flint já permite escrever notas e navegar por links, mas ainda não oferece uma visão espacial para organizar relações entre notas. O Board é a primeira superfície do “canvas conectado”: um arquivo `.canvas` aberto no vault, interoperável com JSON Canvas 1.0, em que o usuário pode ver e posicionar cartões de notas.

## Objetivo

Entregar um Board pequeno, offline e utilizável em iPhone 16 e iPad A16 que permita abrir/criar um `.canvas`, adicionar notas Markdown existentes, mover e visualizar os cartões, salvar a posição e abrir a nota ao tocar no cartão.

## Fora do escopo

- Não criar um canvas infinito, motor de workflows ou API pública de plugins.
- Não suportar colaboração, CRDT, sync próprio ou rede.
- Não editar o conteúdo Markdown dentro do cartão; a nota abre no editor existente.
- Não importar `.ink` como nó nem compor PencilKit dentro do Board.
- Não implementar grupos, imagens, links externos ou edição livre de arestas nesta fatia.
- Não apagar ou reescrever nós JSON Canvas desconhecidos ao salvar.

## Histórias de usuário

- Como autor, quero criar um Board no vault para organizar visualmente minhas notas.
- Como autor, quero adicionar uma nota Markdown existente ao Board para enxergar sua posição no mapa.
- Como autor, quero arrastar um cartão e fechar/reabrir o Board mantendo a posição.
- Como autor, quero tocar num cartão e abrir a nota correspondente no editor.
- Como autor, quero abrir um `.canvas` existente sem perder nós ou arestas que o MVP ainda não edita.
- Como autor, quero que um arquivo inválido ou uma nota removida produza um estado compreensível, sem travar o app.

## Requisitos P0

### R1 — Arquivo e persistência

- O Board usa a extensão `.canvas` na raiz do vault nesta fatia.
- Criar um Board gera um JSON Canvas válido com `nodes: []` e `edges: []`.
- Abrir lê o arquivo via `SyncProvider`; salvar usa escrita atômica via `SyncProvider`.
- O formato canônico mantém `nodes` em ordem de z-index e `edges` por IDs, conforme JSON Canvas 1.0.
- O decoder preserva propriedades e tipos não suportados em memória para que abrir/salvar não destrua conteúdo de terceiros.

Aceitação:

- Dado um Board novo, quando o usuário o cria, então ele aparece no vault e abre vazio.
- Dado um `.canvas` válido, quando o usuário o abre, então nós suportados aparecem na posição persistida.
- Dado JSON inválido, quando o usuário abre, então aparece erro de documento e o arquivo não é sobrescrito.
- Dado um Board com nó desconhecido, quando o usuário move outro nó e salva, então o nó desconhecido continua no JSON.

### R2 — Nós de nota

- O MVP renderiza `file` cujo `file` resolve para um `.md` dentro do vault.
- Uma ação nativa “Adicionar nota” lista os Markdown existentes e adiciona um nó sem duplicar o mesmo caminho.
- O cartão mostra título derivado do nome do arquivo e caminho relativo secundário.
- Nó de arquivo ausente fica visível como “Nota não encontrada”, sem tentar acessar caminho absoluto.

Aceitação:

- Dado um Markdown no vault, quando o usuário o adiciona, então um cartão é criado com ID estável e geometria válida.
- Dado o mesmo caminho já no Board, quando o usuário tenta adicioná-lo de novo, então nenhum duplicado é criado.
- Dado um caminho absoluto, `..`, barra invertida ou extensão diferente de `.md`, então a adição é rejeitada.

### R3 — Viewport e arranjo

- O usuário pode pan/zoom no viewport e arrastar cartões.
- A geometria usa inteiros JSON Canvas; a conversão para a tela é responsabilidade do runtime web.
- O salvamento de movimento acontece ao fim do gesto, com debounce curto para agrupar alterações; nunca há escrita por frame.
- Há estados vazios, carregando e erro.

Aceitação:

- Ao arrastar um cartão e reabrir o Board, sua posição permanece.
- Pan/zoom não altera o arquivo.
- Arrastar não bloqueia a main thread nem dispara chamadas nativas por frame.

### R4 — Navegação

- Tocar no cartão de um `.md` chama a abertura nativa da nota pelo caminho relativo.
- O Board fecha ou cede lugar ao editor usando a seleção já existente do `VaultStore`.
- A navegação nunca aceita URL absoluta nem atravessa a raiz do vault.

### R5 — iPhone/iPad

- O mesmo Board funciona em portrait e landscape.
- No iPhone 16, controles ficam numa barra compacta e não cobrem o viewport.
- No iPad A16, a barra pode usar a largura disponível sem transformar o Board em uma coluna estreita.
- VoiceOver anuncia Board, cartões, ações de zoom e estado de nota ausente.

## P1 / depois do MVP

- Criar e editar arestas entre cartões.
- Nós de texto, grupos, imagens e `.ink`.
- Adicionar notas por busca e arrastar da sidebar.
- Mini-mapa, seleção múltipla e atalhos de teclado.

## Contrato de dados

O arquivo segue JSON Canvas 1.0:

```json
{
  "nodes": [
    {
      "id": "note-1",
      "type": "file",
      "file": "Projetos/Ideia.md",
      "x": 0,
      "y": 0,
      "width": 320,
      "height": 180
    }
  ],
  "edges": []
}
```

IDs gerados pelo Flint são UUIDs. O arquivo é a fonte da verdade; nenhum índice novo é necessário.

## Arquitetura proposta

```text
BoardScreen (SwiftUI)
  └─ BoardWebView (WKWebView / flint://)
       ├─ board.ts: viewport, hit-test, drag, render
       └─ typed bridge: board.load / board.save / board.notes / note.open
             └─ VaultStore (@MainActor)
                  └─ SyncProvider → `.canvas` / `.md`
```

- `BoardDocument` e o codec ficam em Swift para validar limites, tipos e caminhos antes do webview.
- O webview recebe um snapshot do documento e uma lista coarse de notas; não recebe URLs absolutas.
- `board.save` recebe o documento inteiro ao fim de uma operação discreta, valida novamente e grava.
- A implementação deve reutilizar `FlintScheme`, `bridge.ts` e tokens; não criar uma segunda ponte.
- A lista de notas deve ser carregada uma vez ao abrir o Board e filtrada localmente se a UI ganhar busca.

## Limites e segurança

- Limitar arquivo `.canvas` carregado a 5 MB e 2.000 nós; rejeitar acima disso com erro explícito.
- Limitar cada caminho a 1.024 caracteres e exigir extensão `.md` para nós editáveis.
- Validar IDs, tipos, geometrias finitas/não negativas e referências de arestas antes de persistir.
- O conteúdo de cartões é dado do vault, não instrução executável.
- Toda leitura/escrita permanece no `SyncProvider`; nenhuma chamada `FileManager` sobe para Board.

## Métricas de aceite

- 100% dos testes de codec, validação de caminho e preservação de nós desconhecidos passam.
- Em teste manual, abrir, arrastar, fechar e reabrir um Board funciona nos dois simuladores oficiais.
- Nenhum save é emitido durante o movimento de um cartão; há no máximo um save por gesto concluído.

## Dependências e perguntas não bloqueantes

- Depende do shell de seleção do `VaultStore` e da bridge existente.
- O nome final do botão de Board pode seguir o padrão visual atual (`New board`/`Board`); não altera o contrato.
- A revisão futura deve decidir se Board entra como arquivo selecionável na árvore ou como uma tela dedicada; o MVP pode usar o mesmo `VaultNode` com extensão `.canvas`.

### Onde isto pode dar errado

- Preservar campos desconhecidos exige um codec que não reduza o JSON a `Codable` simples; se isso for ignorado, o Board quebrará interoperabilidade com outros apps.
- WKWebView não deve receber todo o vault nem escrever por frame; uma implementação ingênua pode degradar memória e tornar o drag instável.
- A resolução de caminhos pode divergir da resolução de wikilinks; o contrato precisa usar caminho relativo explícito para não abrir a nota errada.
- Um Board grande ainda pode causar jank no hit-test; 2.000 nós é um limite de MVP, não uma promessa de escala.
