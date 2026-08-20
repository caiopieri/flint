import SwiftUI

/// Native chat surface: conversation in the middle, model configuration in the
/// navigation bar, and a persistent composer above the keyboard.
struct AIChatSheet: View {
    let vault: VaultStore
    let modelStore: ModelStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var prompt = ""
    @State private var messages: [AIChatMessage] = []
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var isModelSettingsShown = false
    @FocusState private var promptFocused: Bool
    private let provider = LocalLlamaProvider()

    private var selectedModel: AIModelDescriptor? {
        guard let id = modelStore.selectedModelID else { return nil }
        return modelStore.models.first(where: { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: FlintSpace.s4) {
                        if messages.isEmpty { emptyState }
                        ForEach(messages) { message in messageBubble(message) }
                        if isGenerating, let last = messages.last, last.role == .assistant, last.text.isEmpty {
                            ProgressView().tint(FlintColor.accent).padding(.leading, FlintSpace.s4)
                        }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }
                    .padding(.horizontal, FlintSpace.s4)
                    .padding(.top, FlintSpace.s4)
                    .padding(.bottom, FlintSpace.s3)
                }
                .background(FlintColor.bg)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: messages.last?.text) { _, _ in scrollToBottom(proxy) }
            }
            .navigationTitle("Flint AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isModelSettingsShown = true } label: {
                        HStack(spacing: FlintSpace.s1) {
                            Image(systemName: "gearshape")
                            Text(selectedModel?.name ?? "Modelo")
                                .lineLimit(1)
                        }
                    }
                    .accessibilityLabel("Configurar modelo de IA")
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $isModelSettingsShown) {
                AIModelSettingsSheet(modelStore: modelStore)
                    .presentationDetents([.medium, .large])
            }
            .task { selectInstalledModelIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelGeneration() }
            }
            .onDisappear { cancelGeneration() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: FlintSpace.s3) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(FlintColor.accent)
            Text("Converse com seu vault")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FlintColor.textPrimary)
            Text("Pergunte sobre a nota atual e encontre informações nas suas notas. O conteúdo permanece no dispositivo.")
                .font(.body)
                .foregroundStyle(FlintColor.textSecondary)
            if selectedModel == nil {
                Button("Escolher modelo", systemImage: "gearshape") { isModelSettingsShown = true }
                    .buttonStyle(.flintPrimary)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.vertical, FlintSpace.s6)
    }

    @ViewBuilder
    private func messageBubble(_ message: AIChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: FlintSpace.s1) {
                Text(message.role == .user ? "Você" : "Flint")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.role == .user ? FlintColor.accentText : FlintColor.textMuted)
                Text(message.text.isEmpty ? " " : message.text)
                    .font(.body)
                    .foregroundStyle(FlintColor.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, FlintSpace.s3)
            .padding(.vertical, FlintSpace.s2 + 2)
            .background(message.role == .user ? FlintColor.surfaceRaised : FlintColor.surface)
            .overlay(RoundedRectangle(cornerRadius: FlintRadius.md).stroke(FlintColor.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: FlintRadius.md, style: .continuous))
            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .id(message.id)
    }

    private var composer: some View {
        VStack(spacing: FlintSpace.s2) {
            if let downloading = modelStore.downloadingModelID,
               let model = modelStore.models.first(where: { $0.id == downloading }) {
                HStack(spacing: FlintSpace.s2) {
                    ProgressView(value: modelStore.progress).tint(FlintColor.accent)
                    Text("\(Int(modelStore.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(FlintColor.textSecondary)
                    Text(modelStore.isDownloadPaused ? "Pausado \(model.name)" : "Baixando \(model.name)…")
                        .font(.caption)
                        .foregroundStyle(FlintColor.textSecondary)
                    Button(modelStore.isDownloadPaused ? "Continuar" : "Pausar") {
                        if modelStore.isDownloadPaused {
                            modelStore.resumeDownload()
                        } else {
                            modelStore.pauseDownload()
                        }
                    }
                    .font(.caption)
                    Button("Cancelar") { modelStore.cancelDownload() }
                        .font(.caption)
                }
            }
            HStack(alignment: .bottom, spacing: FlintSpace.s2) {
                TextField(selectedModel == nil ? "Escolha um modelo para começar" : "Pergunte ao seu vault…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($promptFocused)
                    .frame(minHeight: 40, maxHeight: 112, alignment: .center)
                    .padding(.horizontal, FlintSpace.s3)
                    .padding(.vertical, FlintSpace.s2)
                    .background(FlintColor.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: FlintRadius.md, style: .continuous))
                    .disabled(isGenerating)
                Button {
                    isGenerating ? cancelGeneration() : ask()
                } label: {
                    Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FlintColor.textOnAccent)
                        .frame(width: 36, height: 36)
                        .background(FlintColor.accent, in: Circle())
                }
                .buttonStyle(.flintPressable)
                .disabled(!isGenerating && (selectedModel == nil || modelStore.downloadingModelID != nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .opacity(!isGenerating && (selectedModel == nil || modelStore.downloadingModelID != nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.45 : 1)
                .accessibilityLabel(isGenerating ? "Parar resposta" : "Enviar pergunta")
            }
        }
        .padding(.horizontal, FlintSpace.s3)
        .padding(.top, FlintSpace.s2)
        .padding(.bottom, FlintSpace.s2)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { FlintColor.border.frame(height: 1) }
    }

    private func selectInstalledModelIfNeeded() {
        guard modelStore.selectedModelID == nil,
              let installed = modelStore.models.first(where: { modelStore.isInstalled($0) }) else { return }
        modelStore.select(installed)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: FlintMotion.base)) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
    }

    private func ask() {
        guard let modelID = modelStore.selectedModelID,
              let modelURL = modelStore.modelURL(for: modelID) else { return }
        let query = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        prompt = ""
        let assistantID = UUID()
        messages.append(AIChatMessage(role: .user, text: query))
        messages.append(AIChatMessage(id: assistantID, role: .assistant, text: ""))
        isGenerating = true
        generationTask = Task {
            do {
                let currentNote: String? = if let path = vault.selectedRelativePath { try? await vault.editorLoad(path) } else { nil }
                let context = await vault.aiContext(query: query, currentNoteText: currentNote)
                let request = AIRequest(modelID: modelID, context: context, modelURL: modelURL, maxTokens: AI.maxGenerationTokens)
                for try await event in provider.stream(request) {
                    if case .token(let token) = event,
                       let index = messages.firstIndex(where: { $0.id == assistantID }) {
                        messages[index].text += token
                    }
                }
            } catch is CancellationError {
                if let index = messages.firstIndex(where: { $0.id == assistantID }), messages[index].text.isEmpty { messages[index].text = "Geração interrompida." }
            } catch {
                if let index = messages.firstIndex(where: { $0.id == assistantID }) { messages[index].text = "Não consegui responder: \(error.localizedDescription)" }
            }
            isGenerating = false
            generationTask = nil
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }
}

private struct AIChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) { self.id = id; self.role = role; self.text = text }
}

private struct AIModelSettingsSheet: View {
    let modelStore: ModelStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Modelo usado pelo chat") {
                    ForEach(modelStore.models) { model in modelRow(model) }
                }
                if let error = modelStore.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(FlintColor.accentText) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FlintColor.bg)
            .navigationTitle("Configurações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: AIModelDescriptor) -> some View {
        let installed = modelStore.isInstalled(model)
        let selected = modelStore.selectedModelID == model.id
        Button { modelStore.select(model) } label: {
            HStack(spacing: FlintSpace.s3) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? FlintColor.accent : FlintColor.textMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name).foregroundStyle(FlintColor.textPrimary)
                    Text(model.detail).font(.caption).foregroundStyle(FlintColor.textSecondary)
                }
                Spacer()
                if modelStore.downloadingModelID == model.id {
                    HStack(spacing: FlintSpace.s1) {
                        ProgressView(value: modelStore.progress).frame(width: 64)
                        Text("\(Int(modelStore.progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(FlintColor.textSecondary)
                    }
                } else {
                    Text(installed ? "Instalado" : "Baixar \(model.sizeLabel)")
                        .font(.caption)
                        .foregroundStyle(installed ? FlintColor.accentText : FlintColor.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if modelStore.downloadingModelID == model.id {
                if modelStore.isDownloadPaused {
                    Button("Continuar") { modelStore.resumeDownload() }.tint(FlintColor.accent)
                } else {
                    Button("Pausar") { modelStore.pauseDownload() }.tint(FlintColor.accent)
                }
                Button("Cancelar") { modelStore.cancelDownload() }.tint(.red)
            }
        }
    }
}
