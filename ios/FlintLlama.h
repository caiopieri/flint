#pragma once

#include <stdint.h>

typedef void * flint_llama_handle;

void flint_llama_backend_init(void);
void flint_llama_backend_free(void);

int32_t flint_llama_load_model(
    const char * path,
    int32_t gpu_layers,
    uint32_t context_size,
    uint32_t batch_size,
    uint32_t micro_batch_size,
    uint32_t sequence_count,
    uint32_t threads,
    flint_llama_handle * model,
    flint_llama_handle * context
);

void flint_llama_unload_model(flint_llama_handle model, flint_llama_handle context);
uint32_t flint_llama_context_size(flint_llama_handle context);
int32_t flint_llama_vocabulary_size(flint_llama_handle model);

int32_t flint_llama_tokenize(
    flint_llama_handle model,
    const char * text,
    int32_t text_length,
    int32_t * tokens,
    int32_t token_capacity
);

int32_t flint_llama_decode_prompt(flint_llama_handle context, int32_t * tokens, int32_t count);
int32_t flint_llama_sample(
    flint_llama_handle model,
    flint_llama_handle context,
    int32_t vocabulary_size,
    int32_t * token,
    char * piece,
    int32_t piece_capacity
);
int32_t flint_llama_decode_token(flint_llama_handle context, int32_t token, int32_t position);
void flint_llama_clear(flint_llama_handle context);
