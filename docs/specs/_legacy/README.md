# Specs legadas (pré-spec-kit)

Estas specs seguem o **formato antigo** do harness bespoke (`research.md` / `plan.md` / `progress.md`,
dos comandos `fic-research/plan/implement`), hoje **aposentado**. Ficam aqui só como referência
histórica — não são o processo atual.

- `search/` — busca FTS5 (GRDB). **Implementada e testada** (ver `progress.md`).
- `frontmatter-tags-theme/` — frontmatter/tags + tema dark/light.

## O processo agora

O Flint migrou para o **github/spec-kit**. As novas specs vivem em `specs/NNN-nome/{spec,plan,tasks}.md`
na raiz do repo, geradas por `/speckit.specify → clarify → plan → tasks → analyze → implement`.
A lei do projeto está em `docs/constitution.md` (colada via `/speckit.constitution`). Visão geral do
fluxo no harness: `Orquestrador/dev-harness/` (`PLAYBOOK.md`, `spec-kit-adocao.md`).
