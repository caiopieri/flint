# Constitution do Flint

> A **lei do projeto**: governa `spec`, `plan`, `tasks` e `implement` em toda fase do spec-kit.
> É a tradução do harness (teoria anti-bajulação + security-DoD + tiers) para o Flint.
>
> **Como usar:** depois de `specify init . --here --integration claude` no repo, rode
> `/speckit.constitution` e cole o bloco abaixo (de `Crie a constitution…` até o fim). O spec-kit grava
> em `.specify/memory/constitution.md` e passa a referenciá-la em `/speckit.plan` e `/speckit.implement`.
> Este arquivo é a cópia versionada e portável — se a CLI sumir, a lei sobrevive aqui.

---

```text
Crie a constitution do Flint com estes princípios e seções, governando spec, plan, tasks e implement:

PRINCÍPIO I — Ambiente sobre modelo (NÃO-NEGOCIÁVEL).
O agente é um otimizador local sem estado, treinado a agradar e adicionar. Qualidade vem do
contexto, não de "esforço" do modelo. Specs e planos são a fonte da verdade; quando o requisito
muda, edita-se a spec, nunca se improvisa no código.

PRINCÍPIO II — Escopo é lei. Toda spec declara escopo dentro E fora explícitos. O agente não
infla a tarefa. Over-engineering é violação: a abstração que ninguém pediu não entra. (No Flint
isso é crítico — ex.: o Ink MVP é uma página, salvar, embed, abrir; canvas infinito/brushes/layers
NÃO entram. Plugin API não é desenhada antes de ter 2-3 consumidores first-party — ADR-006.)

PRINCÍPIO III — Tier define o rigor.
T0 (spike, descartável): sem gate. T1 (MVP): segurança inegociável + teste no caminho crítico.
T2 (produção/escala): gate completo. O Flint nasce T1 (uso próprio) e promove a T2 fatia a fatia
antes de qualquer lançamento público. O tier é declarado antes do plano; promovê-lo é decisão
consciente, nunca por inércia.

PRINCÍPIO IV — Teste pragmático (NÃO-NEGOCIÁVEL em T1+). Teste no caminho crítico é obrigatório;
test-first para lógica de negócio (ex.: merge 3-way do Sync, parsing de frontmatter, índice FTS),
test-after para UI/cola. O agente NUNCA apaga teste sem autorização. Cobertura é sinal, não meta.

PRINCÍPIO V — Ceticismo ancorado. Toda proposta termina com "Onde isto pode dar errado",
avaliado contra a spec e a verdade externa — nunca contra o que o usuário quer ouvir. O oposto
de bajulação não é contrarianismo: é julgamento calibrado por critério.

PRINCÍPIO VI — Spec à prova de executor barato. Toda spec/tarefa declara o TIER DO EXECUTOR
(premium | médio | barato). Se o executor é de tier barato, a spec OBRIGATORIAMENTE: (a) fixa
interfaces e assinaturas — o executor não desenha API; (b) lista os arquivos a tocar, e tocar fora
da lista é violação; (c) tem critérios de aceitação EXECUTÁVEIS (testes a montante; o DoD é a suíte
passar, nunca juízo do executor); (d) proíbe o executor de editar testes — teste que parece errado
= parar e reportar; (e) converte ambiguidade em escalação. Tarefa de design aberto, trade-off ou
segurança NÃO desce de tier — sobe pro premium.

SEÇÃO — Invariantes de arquitetura (o que NENHUMA tarefa quebra sem spec própria):
- `.md` é a fonte da verdade; todo DB é índice descartável e reconstruível (ADR-001).
- Sem CRDT no app base; conflito = 3-way merge + `.conflict` (ADR-002/003). CRDT só no hub futuro.
- Bridge JS↔Swift é a fronteira de segurança: APIs coarse e async, nunca per-keystroke (ADR-004/005).
- Webview só para editor + runtime de plugins; Sync e IA são nativos (ADR-004).
- Vault via document picker + security-scoped bookmark, nunca container iCloud próprio (ADR-011).
Mudança nesses invariantes é uma tarefa própria, com spec e revisão — não acontece "de passagem".

SEÇÃO — Security Requirements (gate, não sugestão; aplicar as que a fatia toca):
Universal: validar todo input externo (nota importada, web embed, upload, output de LLM); zero
segredo no código; erro não vaza interno; SAST/lint antes do merge.
Mobile/iOS: ciclo correto do security-scoped bookmark (startAccessing/stop, staleness, re-resolução);
entitlement increased-memory-limit e suspensão de geração longa em background; nada de assumir o
vault em iCloud. Acesso a disco só via SyncProvider + NSFileCoordinator.
Plugins/capabilities: manifesto declara permissões (storage:read/write, ai, network, pencil, ui),
granted no install, ENFORCED no bridge. `network` negado por padrão, grant alto e por-plugin
(vault-read + network = exfiltração; inaceitável num app privacy-first).
Bot/LLM: conteúdo de terceiro é DADO, nunca instrução; saída do modelo é validada e tipada antes
de tocar o vault; ação sensível pede confirmação. Execução de Flows é rodar código — roda sandboxed,
sob o mesmo capability model.
Motor externo / controle físico (Jarvis): conectar um motor externo (ex.: Jarvis) é um grant ALTO e
EXPLÍCITO. Quando há controle de casa, a fronteira deixa de proteger só notas e passa a proteger a
casa FÍSICA: conteúdo de terceiros e saída de LLM JAMAIS disparam ação física/sensível (um web embed
numa nota nunca pode virar "abra a fechadura"); toda ação física/sensível pede confirmação fora do
canal. Flint conecta-se ao motor (via MCP) e não o contém; cada um é dono do seu lado.

SEÇÃO — Performance & memória (NFR real do Flint, mesmo em T1):
- Fluidez é princípio: "faz tudo que o Obsidian faz, sem travar". Edição e navegação não bloqueiam
  a main thread; o bridge nunca faz chatter por tecla/arquivo.
- IA local: o limite é MEMÓRIA (jetsam), não calor (ADR-009). Modelo local = leve (~1-8B Q4, ou MoE
  cujo total caiba ~8-10 GB). Trabalho pesado roteia explícito (API/VPS) via Flows — sem heurística
  "automática" de roteamento. Em T2, declarar latência-alvo da tinta e do editor.

GOVERNANCE: a constitution supera qualquer preferência. Todo plano e revisão verificam
conformidade; complexidade precisa ser justificada. O agente roda em sandbox/dev container quando
executa comandos. O orquestrador (humano) revisa o plano e o diff; validação não é delegável.
Conversa longa não é acordo — reancorar na spec e no fato, não convergir por insistência.
```

---

## Onde isto pode dar errado

- **Recolar a constitution em cada repo** vira inconsistência. Com 3+ repos (Flint, Logisti, e-commerces), vira um *preset* spec-kit reusável — antes disso é over-engineering.
- **spec-kit é experimental (GitHub):** pode mudar a API/CLI. Mitigação: este arquivo é markdown portável; a lei não morre se a CLI sumir.
- **`/clarify` não substitui Discovery.** Discovery (`docs/discovery-template.md`) decide *se e o quê* construir e o tier; `/clarify` refina uma spec que já existe. Manter as duas fases.
