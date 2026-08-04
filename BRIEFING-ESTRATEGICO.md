# BRIEFING ESTRATÉGICO — Flint

> **Para:** o agente dono deste projeto. **De:** estrategista (leitura de 2026-07-04: ROADMAP, README, visão no vault).
> **Posição no mapa:** Núcleo 1 — a superfície. E, estrategicamente, **o teste de estresse da fábrica**: é o produto mais difícil do portfólio sendo construído pelo dev-harness.

## O que eu vi (avaliação honesta)

Engenharia de gente grande: trilha do editor substancialmente construída (vault picker, CodeMirror 6 com bridge tipada, FTS5, merge 3-way com fallback `.conflict`), ADRs numerados, roadmap com "riskiest hypothesis" nomeada por fatia. A decisão do Ink Notebook como arquivo `.ink` próprio com embed — adiando o pesadelo de compositing nativo-sobre-webview — é exatamente o tipo de corte que salva projetos. O plano está certo; meus insights são sobre **sequência e teto de risco**.

## Insights do estrategista

1. **O fosso é o Ink, mas o "valley of death" é o daily-driver.** O Ink Notebook MVP (Now) ataca a hipótese mais arriscada — correto. Mas atenção à armadilha da ordem: se o Ink chegar bom e o editor ainda não substituir o Obsidian iOS no dia a dia do fundador, o app vira demo. O gate honesto de v1 é **o fundador apagar o GoodNotes E o Obsidian do iPhone por 2 semanas** e não voltar. Dogfood é o único QA que não mente aqui.

2. **A fatia fina de IA vale mais pelo harness que pela feature.** "Busca no vault + resumo com nota como contexto" parece pequena, mas é onde nasce a camada provider-agnostic — a decisão barata-agora-cara-depois que a visão já pregou. Blindem o contrato de provider com teste desde o primeiro commit; o Jarvis-provider e o on-device são plugues no MESMO soquete ou o retrofit vai doer.

3. **Board em JSON Canvas aberto é jogada estratégica dupla** — formato aberto = interop com Obsidian (migração indolor de quem importa) e é o substrato do futuro mapa vivo da Meta-fábrica. Só não deixem o Board puxar o Plugin API antes da hora (ADR-006 já protege isso — mantenham).

4. **O live map da fábrica está corretamente marcado "not startable".** Protejam essa honestidade: enquanto o canvas engine não existir, qualquer trabalho no mapa vivo é castelo no ar. A ponte real com a fábrica, na ordem: canvas engine → cliente MCP → só então renderizar UM run real no nível meso.

5. **Open source como estratégia, não só licença.** O fosso do Flint (tinta + canvas + IA numa superfície) é combinação, não segredo. Comunidade cedo = distribuição de graça no nicho Obsidian+GoodNotes, que é exatamente onde moram os primeiros mil usuários. O README já vende bem; quando o Ink MVP passar no dogfood, um vídeo de 90 segundos vale mais que qualquer feature do Next.

## Prioridade (o que provar em seguida)

1. Ink Notebook MVP (as 6 PRs do handoff já fatiadas) → gate de dogfood real.
2. Fechar os gaps do editor daily-driver (confirmar em Discovery, como planejado).
3. Fatia fina de IA com contrato provider-agnostic testado.

## Fora de escopo agora

PDF annotation, Plugin API, Flows, sync hub próprio, NAS-client, E2EE backup, live map — tudo já corretamente em Later; a função deste briefing é dar força ao "não" quando a tentação vier.

## Missão cumprida quando

O fundador vive 2 semanas com Flint como único app de notas do iPhone/iPad (escrita + tinta + busca), sem abrir Obsidian nem GoodNotes — e o repo tem release público instalável por outra pessoa.
