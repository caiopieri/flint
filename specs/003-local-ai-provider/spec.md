# Spec — Local AI provider and streamed answer

## Goal

Connect an explicitly installed local GGUF model to Flint's native AI chat so the user can ask a read-only question using bounded vault context and see the answer arrive incrementally.

## In scope

- `AIProvider` contract with started, token, and finished events.
- Native `LocalLlamaProvider` backed by the pinned llama.cpp XCFramework.
- Serialized model/context lifecycle behind an actor and a small C API shim.
- Chat asks the selected installed model and appends streamed tokens.
- Clear errors for missing/invalid model, oversized context, decode failure, and cancellation.

## Out of scope

- Remote/API providers, model-specific chat-template tuning, tools, autonomous actions, vault writes, background generation, and model update orchestration.
- Proving generation throughput on Simulator; physical-device acceptance is a separate manual gate.

## Acceptance

1. The ask control remains unavailable until a catalog model is installed.
2. With an installed model, a question uses the current note plus bounded FTS context and renders answer tokens as they arrive.
3. No AI call crosses the WebView bridge per token and no model binary is written into the vault.
4. A cancelled or failed request leaves the chat usable and does not mutate vault files.
5. Build, type-check, and unit tests pass for iPhone 16 and iPad A16 simulator destinations; physical inference remains explicitly marked pending until tested with a downloaded model.
