# Spec — AI model catalog and explicit download

**Tier:** T1 · **Executor:** premium

## Objetivo

Permitir que a pessoa escolha um modelo recomendado dentro do chat do Flint e
baixe-o com progresso visível. O arquivo instalado deve ficar fora do vault e
ser validado antes de poder ser usado pelo provider local.

## Dentro do escopo

- Catálogo estático de modelos GGUF revisados, com URL HTTPS, tamanho esperado e SHA-256.
- Download nativo via `URLSession`, iniciado apenas por ação explícita do usuário.
- Estado de progresso, cancelamento, erro e instalado no seletor de modelos.
- Armazenamento em `Application Support/Flint/Models`.
- Arquivo temporário, validação de tamanho e checksum, e promoção atômica para o destino.
- Primeiro painel nativo do chat, deixando explícito quando o provider ainda não está conectado.

## Fora do escopo

- Inferência, streaming de tokens ou carregamento llama.cpp/Metal.
- Download automático, atualização silenciosa ou catálogo remoto.
- Retomada de download em background.
- API key, provider remoto e sincronização dos modelos entre dispositivos.

## Critérios de aceitação

1. O painel exibe os modelos recomendados e seus tamanhos antes de qualquer download.
2. Um toque em “Baixar” mostra progresso e permite cancelar sem deixar arquivo instalado.
3. URL que não seja HTTPS, tamanho incorreto ou checksum incorreto nunca promove o arquivo.
4. Um modelo validado aparece como instalado após reabrir o painel.
5. Nenhum arquivo do modelo é criado dentro do vault.
6. O catálogo e as regras de validação têm testes unitários; typecheck, testes e build passam.
