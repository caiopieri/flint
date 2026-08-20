// LocalLlamaProvider — native llama.cpp/Metal adapter.
//
// The engine is actor-isolated because llama contexts are mutable and cannot
// be shared between concurrent generations. The WebView never sees this API.
import Foundation
import FlintLlama

struct LocalLlamaProvider: AIProvider {
    let id = "local.llama.cpp"
    private let engine = LocalLlamaEngine()

    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await engine.generate(request) { event in
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private actor LocalLlamaEngine {
    private struct Handle: @unchecked Sendable {
        let rawValue: UnsafeMutableRawPointer
    }

    private var model: Handle?
    private var context: Handle?
    private var loadedPath: String?
    private var didInitializeBackend = false

    deinit {
        flint_llama_unload_model(model?.rawValue, context?.rawValue)
        if didInitializeBackend { flint_llama_backend_free() }
    }

    func generate(
        _ request: AIRequest,
        emit: @escaping @Sendable (AIEvent) -> Void
    ) throws {
        try Task.checkCancellation()
        emit(.started)
        try loadModel(at: request.modelURL)
        guard let model, let context else { throw AIProviderError.invalidModel }
        defer { flint_llama_clear(context.rawValue) }

        let prompt = AI.prompt(for: request.context, modelID: request.modelID)
        var tokens = try tokenize(prompt, model: model)
        guard !tokens.isEmpty else { throw AIProviderError.contextTooLarge }
        let maximumTokens = min(max(request.maxTokens, 1), AI.maxGenerationTokens)
        let contextSize = Int(flint_llama_context_size(context.rawValue))
        guard contextSize > 0, tokens.count + maximumTokens < contextSize else {
            throw AIProviderError.contextTooLarge
        }

        let promptCount = tokens.count
        let promptResult = tokens.withUnsafeMutableBufferPointer { buffer in
            flint_llama_decode_prompt(context.rawValue, buffer.baseAddress, Int32(buffer.count))
        }
        guard promptResult >= 0 else {
            throw AIProviderError.decodeFailed
        }

        let vocabularyCount = Int(flint_llama_vocabulary_size(model.rawValue))
        var generated = 0
        let stopSequences = AI.stopSequences(for: request.modelID)
        generation: while generated < maximumTokens {
            try Task.checkCancellation()
            var token: Int32 = 0
            var pieceBuffer = [CChar](repeating: 0, count: 256)
            let sampleResult = pieceBuffer.withUnsafeMutableBufferPointer { pieceBuffer in
                flint_llama_sample(
                    model.rawValue,
                    context.rawValue,
                    Int32(vocabularyCount),
                    &token,
                    pieceBuffer.baseAddress,
                    Int32(pieceBuffer.count)
                )
            }
            if sampleResult == 1 { break }
            guard sampleResult >= 0 else { throw AIProviderError.decodeFailed }
            let piece = String(
                decoding: pieceBuffer.prefix(Int(sampleResult)).map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            if let stop = stopSequences.first(where: { piece.contains($0) }) {
                if let range = piece.range(of: stop) {
                    let prefix = String(piece[..<range.lowerBound])
                    if !prefix.isEmpty { emit(.token(prefix)) }
                }
                break generation
            }
            if !piece.isEmpty { emit(.token(piece)) }
            generated += 1

            guard flint_llama_decode_token(context.rawValue, token, Int32(promptCount + generated - 1)) >= 0 else {
                throw AIProviderError.decodeFailed
            }
        }

        emit(.finished)
    }

    private func loadModel(at url: URL) throws {
        guard url.isFileURL else { throw AIProviderError.invalidModel }
        if loadedPath == url.path, model != nil, context != nil { return }

        flint_llama_unload_model(model?.rawValue, context?.rawValue)
        context = nil
        self.model = nil
        loadedPath = nil

        if !didInitializeBackend {
            flint_llama_backend_init()
            didInitializeBackend = true
        }

        let threads = UInt32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount)))
        var loadedModel: UnsafeMutableRawPointer?
        var loadedContext: UnsafeMutableRawPointer?
        let result = url.path.withCString { path in
            flint_llama_load_model(
                path,
                99,
                4096,
                512,
                512,
                1,
                threads,
                &loadedModel,
                &loadedContext
            )
        }
        guard result == 0, let loadedModel, let loadedContext else {
            throw AIProviderError.modelLoadFailed
        }
        model = Handle(rawValue: loadedModel)
        context = Handle(rawValue: loadedContext)
        loadedPath = url.path
    }

    private func tokenize(_ prompt: String, model: Handle) throws -> [Int32] {
        let required = prompt.withCString { text in
            flint_llama_tokenize(model.rawValue, text, Int32(prompt.utf8.count), nil, 0)
        }
        guard required < 0 else { throw AIProviderError.contextTooLarge }
        var tokens = [Int32](repeating: 0, count: Int(-required))
        let count = prompt.withCString { text in
            tokens.withUnsafeMutableBufferPointer { buffer in
                flint_llama_tokenize(model.rawValue, text, Int32(prompt.utf8.count), buffer.baseAddress, Int32(buffer.count))
            }
        }
        guard count > 0 else { throw AIProviderError.contextTooLarge }
        tokens.removeSubrange(Int(count)..<tokens.count)
        return tokens
    }

}
