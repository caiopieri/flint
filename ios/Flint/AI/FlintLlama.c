#include "../../FlintLlama.h"

#include <llama/llama.h>

#include <float.h>
#include <stddef.h>

void flint_llama_backend_init(void) {
    llama_backend_init();
}

void flint_llama_backend_free(void) {
    llama_backend_free();
}

int32_t flint_llama_load_model(
    const char * path,
    int32_t gpu_layers,
    uint32_t context_size,
    uint32_t batch_size,
    uint32_t micro_batch_size,
    uint32_t sequence_count,
    uint32_t threads,
    flint_llama_handle * model_out,
    flint_llama_handle * context_out
) {
    struct llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = gpu_layers;

    struct llama_model * model = llama_load_model_from_file(path, model_params);
    if (model == NULL) {
        return -1;
    }

    struct llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = context_size;
    context_params.n_batch = batch_size;
    context_params.n_ubatch = micro_batch_size;
    context_params.n_seq_max = sequence_count;
    context_params.n_threads = threads;
    context_params.n_threads_batch = threads;

    struct llama_context * context = llama_new_context_with_model(model, context_params);
    if (context == NULL) {
        llama_free_model(model);
        return -1;
    }

    *model_out = (flint_llama_handle) model;
    *context_out = (flint_llama_handle) context;
    return 0;
}

void flint_llama_unload_model(flint_llama_handle model_handle, flint_llama_handle context_handle) {
    if (context_handle != NULL) {
        llama_free((struct llama_context *) context_handle);
    }
    if (model_handle != NULL) {
        llama_free_model((struct llama_model *) model_handle);
    }
}

uint32_t flint_llama_context_size(flint_llama_handle context) {
    return llama_n_ctx((struct llama_context *) context);
}

int32_t flint_llama_vocabulary_size(flint_llama_handle model) {
    return llama_n_vocab((struct llama_model *) model);
}

int32_t flint_llama_tokenize(
    flint_llama_handle model,
    const char * text,
    int32_t text_length,
    int32_t * tokens,
    int32_t token_capacity
) {
    return llama_tokenize(
        (struct llama_model *) model,
        text,
        text_length,
        (llama_token *) tokens,
        token_capacity,
        true,
        true
    );
}

int32_t flint_llama_decode_prompt(flint_llama_handle context, int32_t * tokens, int32_t count) {
    llama_batch batch = llama_batch_get_one((llama_token *) tokens, count, 0, 0);
    return llama_decode((struct llama_context *) context, batch);
}

int32_t flint_llama_sample(
    flint_llama_handle model_handle,
    flint_llama_handle context_handle,
    int32_t vocabulary_size,
    int32_t * token_out,
    char * piece,
    int32_t piece_capacity
) {
    struct llama_model * model = (struct llama_model *) model_handle;
    struct llama_context * context = (struct llama_context *) context_handle;
    float * logits = llama_get_logits(context);
    if (logits == NULL || vocabulary_size <= 0) {
        return -1;
    }

    int32_t best_token = 0;
    float best_logit = -FLT_MAX;
    for (int32_t index = 0; index < vocabulary_size; index++) {
        if (logits[index] > best_logit) {
            best_logit = logits[index];
            best_token = index;
        }
    }

    if (llama_token_is_eog(model, (llama_token) best_token)) {
        return 1;
    }

    int32_t piece_length = llama_token_to_piece(
        model,
        (llama_token) best_token,
        piece,
        piece_capacity,
        false
    );
    if (piece_length < 0) {
        return -1;
    }

    *token_out = best_token;
    return piece_length;
}

int32_t flint_llama_decode_token(flint_llama_handle context_handle, int32_t token, int32_t position) {
    llama_token mutable_token = (llama_token) token;
    llama_batch batch = llama_batch_get_one(&mutable_token, 1, position, 0);
    return llama_decode((struct llama_context *) context_handle, batch);
}

void flint_llama_clear(flint_llama_handle context) {
    llama_kv_cache_clear((struct llama_context *) context);
}
