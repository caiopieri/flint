import PencilKit
import SwiftUI

struct InkScreen: View {
    let vault: VaultStore
    let relativePath: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var paper: InkDocument.Paper = .dotted
    @State private var drawing = PKDrawing()
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        InkCanvasView(drawing: $drawing, paper: paper, onDrawingChanged: scheduleSave)
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Paper", selection: $paper) {
                        ForEach(InkDocument.Paper.allCases, id: \.self) { paper in
                            Text(paper.rawValue.capitalized).tag(paper)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle(URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: relativePath) { await load() }
            .onChange(of: paper) { _, _ in scheduleSave() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { flushSave() }
            }
            .onDisappear { flushSave() }
    }

    private func load() async {
        do {
            let doc = try await vault.inkLoad(relativePath)
            paper = doc.paper
            drawing = doc.drawingData.isEmpty ? PKDrawing() : (try? PKDrawing(data: doc.drawingData)) ?? PKDrawing()
            isLoaded = true
        } catch {
            isLoaded = true
            vault.errorMessage = "Couldn't open drawing: \(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        guard isLoaded else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await saveNow()
        }
    }

    private func flushSave() {
        guard isLoaded else { return }
        saveTask?.cancel()
        saveTask = nil
        Task { await saveNow() }
    }

    private func saveNow() async {
        let doc = InkDocument(paper: paper, drawingData: drawing.dataRepresentation())
        do {
            try await vault.inkSave(relativePath, doc)
        } catch {
            vault.errorMessage = "Couldn't save drawing: \(error.localizedDescription)"
        }
    }
}
