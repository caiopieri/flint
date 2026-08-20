# Spec — AI prompt templates and cooperative cancellation

## Objetivo

Endurecer o primeiro chat local do Flint para que os modelos recomendados recebam
um formato de conversa compatível, o conteúdo do vault permaneça claramente como
dados de referência e uma geração possa ser interrompida ao sair da tela ou ao
entrar em background.

## Dentro

- Template ChatML para Qwen3, template de instrução para Phi-4 Mini e fallback
  determinístico para outros modelos.
- Marcadores explícitos para contexto do vault e pergunta do usuário.
- Limite de saída de 512 tokens e reserva desse espaço no contexto do modelo.
- Cancelamento cooperativo entre SwiftUI, `AsyncThrowingStream` e o actor nativo.
- Limpeza do KV cache em sucesso, erro ou cancelamento.
- Testes unitários dos templates, fallback e sequências de parada.

## Fora

- Fine-tuning, avaliação de qualidade automática ou troca de modelos.
- Tools, escrita no vault, provider remoto e geração em background.
- Streaming de tokens pelo WebView.

## Aceitação

1. Qwen3 e Phi-4 recebem templates distintos; modelo desconhecido usa fallback.
2. Conteúdo da nota aparece entre marcadores de referência e não é tratado como
   instrução de sistema pelo prompt.
3. A geração não ultrapassa 512 tokens nem consome todo o contexto disponível.
4. Parar, sair da sheet ou entrar em background cancela a geração e deixa o chat
   disponível para uma nova pergunta.
5. Build, type-check e testes passam nos destinos oficiais iPhone 16 e iPad A16.

## Tier do executor

Premium — mudança de comportamento de inferência e ciclo de vida nativo.
