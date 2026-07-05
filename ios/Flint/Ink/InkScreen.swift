import PencilKit
import SwiftUI

struct InkScreen: View {
    let vault: VaultStore
    let relativePath: String

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var draft = InkDrawingDraft()
    @State private var notebook = InkNotebook()
    @State private var currentPageIndex = 0
    @State private var canvasRevision = 0
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var deleteConfirmation = false
    @State private var isPageOverviewPresented = false

    var body: some View {
        VStack(spacing: 0) {
            controlsBar
            divider

            InkCanvasView(
                drawing: draft.drawing,
                drawingRevision: canvasRevision,
                paper: currentPaper,
                onDrawingChanged: drawingDidChange
            )
            .ignoresSafeArea(edges: .bottom)

            divider
        }
        .navigationTitle(URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: relativePath) { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushSave() }
        }
        .onDisappear { flushSave() }
        .confirmationDialog(
            "Delete this page?",
            isPresented: $deleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete page", role: .destructive) {
                deleteCurrentPage()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The notebook keeps at least one page.")
        }
        .sheet(isPresented: $isPageOverviewPresented) {
            NavigationStack {
                InkPageOverview(
                    pages: $notebook.pages,
                    currentIndex: currentPageIndex,
                    onSelect: selectPage,
                    onReorder: reorderPages,
                    onAdd: addPage
                )
            }
        }
    }

    private var controlsBar: some View {
        HStack(spacing: FlintSpace.s2) {
            pageControls
                .frame(width: horizontalSizeClass == .compact ? 126 : 142, alignment: .leading)

            Spacer(minLength: FlintSpace.s2)

            Button {
                persistDraftToCurrentPage()
                isPageOverviewPresented = true
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            .buttonStyle(.flintIcon)

            paperMenu

            Button {
                addPage()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.flintIcon)

            Button(role: .destructive) {
                deleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(notebook.pages.count <= 1)
            .buttonStyle(.flintIcon)
        }
        .padding(.horizontal, FlintSpace.s4)
        .padding(.vertical, FlintSpace.s2)
        .background(FlintColor.surface)
    }

    private var pageControls: some View {
        HStack(spacing: FlintSpace.s1) {
            Button {
                stepPage(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPageIndex == 0)
            .buttonStyle(.flintIcon)

            Button {
                stepPage(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPageIndex >= notebook.pages.count - 1)
            .buttonStyle(.flintIcon)

            Text("\(currentPageIndex + 1)/\(notebook.pages.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var paperMenu: some View {
        Menu {
            ForEach(InkNotebook.Paper.allCases, id: \.self) { paper in
                Button {
                    paperBinding.wrappedValue = paper
                } label: {
                    Label(paper.label, systemImage: paper.symbolName)
                }
            }
        } label: {
            if horizontalSizeClass == .compact {
                Image(systemName: currentPaper.symbolName)
                    .frame(width: 44, height: 36)
            } else {
                Label(currentPaper.label, systemImage: currentPaper.symbolName)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("Paper: \(currentPaper.label)")
    }

    private var divider: some View {
        FlintColor.border.frame(height: 1)
    }

    private var currentPaper: InkNotebook.Paper {
        guard notebook.pages.indices.contains(currentPageIndex) else { return .dotted }
        return notebook.pages[currentPageIndex].paper
    }

    private var paperBinding: Binding<InkNotebook.Paper> {
        Binding(
            get: { currentPaper },
            set: { newPaper in
                guard notebook.pages.indices.contains(currentPageIndex) else { return }
                notebook.pages[currentPageIndex].paper = newPaper
                scheduleSave()
            }
        )
    }

    private func stepPage(_ delta: Int) {
        let next = min(max(currentPageIndex + delta, 0), max(notebook.pages.count - 1, 0))
        guard next != currentPageIndex else { return }
        selectPage(next)
    }

    private func selectPage(_ index: Int) {
        guard notebook.pages.indices.contains(index), index != currentPageIndex else { return }
        persistDraftToCurrentPage()
        currentPageIndex = index
        loadCurrentPageIntoDraft()
        scheduleSave()
    }

    private func reorderPages(from offsets: IndexSet, to destination: Int) {
        guard !offsets.isEmpty else { return }
        persistDraftToCurrentPage()
        let currentPageID = notebook.pages.indices.contains(currentPageIndex)
            ? notebook.pages[currentPageIndex].id
            : nil

        notebook.pages.move(fromOffsets: offsets, toOffset: destination)
        if let currentPageID,
           let newIndex = notebook.pages.firstIndex(where: { $0.id == currentPageID }) {
            currentPageIndex = newIndex
        } else {
            currentPageIndex = min(currentPageIndex, max(notebook.pages.count - 1, 0))
        }
        loadCurrentPageIntoDraft()
        scheduleSave()
    }

    private func addPage() {
        persistDraftToCurrentPage()
        notebook.pages.append(.init())
        currentPageIndex = notebook.pages.count - 1
        loadCurrentPageIntoDraft()
        scheduleSave()
    }

    private func deleteCurrentPage() {
        guard notebook.pages.count > 1, notebook.pages.indices.contains(currentPageIndex) else { return }
        notebook.pages.remove(at: currentPageIndex)
        currentPageIndex = min(currentPageIndex, notebook.pages.count - 1)
        loadCurrentPageIntoDraft()
        scheduleSave()
    }

    private func load() async {
        do {
            let loaded = try await vault.notebookLoad(relativePath)
            notebook = loaded.pages.isEmpty ? InkNotebook() : loaded
            currentPageIndex = min(currentPageIndex, notebook.pages.count - 1)
            loadCurrentPageIntoDraft()
            isLoaded = true
        } catch {
            isLoaded = true
            vault.errorMessage = "Couldn't open notebook: \(error.localizedDescription)"
        }
    }

    private func drawingDidChange(_ drawing: PKDrawing) {
        draft.drawing = drawing
        scheduleSave()
    }

    private func loadCurrentPageIntoDraft() {
        guard notebook.pages.indices.contains(currentPageIndex) else {
            draft.drawing = PKDrawing()
            canvasRevision += 1
            return
        }

        let data = notebook.pages[currentPageIndex].drawingData
        draft.drawing = data.isEmpty ? PKDrawing() : (try? PKDrawing(data: data)) ?? PKDrawing()
        canvasRevision += 1
    }

    private func persistDraftToCurrentPage() {
        guard notebook.pages.indices.contains(currentPageIndex) else { return }
        notebook.pages[currentPageIndex].drawingData = draft.drawing.dataRepresentation()
    }

    private func scheduleSave() {
        guard isLoaded else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
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
        persistDraftToCurrentPage()
        do {
            try await vault.notebookSave(relativePath, notebook)
        } catch {
            vault.errorMessage = "Couldn't save notebook: \(error.localizedDescription)"
        }
    }
}

@MainActor
private final class InkDrawingDraft: ObservableObject {
    var drawing = PKDrawing()
}

private extension InkNotebook.Paper {
    var label: String {
        switch self {
        case .blank: return "Blank"
        case .lined: return "Lined"
        case .grid: return "Grid"
        case .dotted: return "Dots"
        }
    }

    var symbolName: String {
        switch self {
        case .blank: return "doc"
        case .lined: return "list.bullet"
        case .grid: return "grid"
        case .dotted: return "circle.grid.2x2"
        }
    }
}
