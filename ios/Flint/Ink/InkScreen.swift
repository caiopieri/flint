import PencilKit
import SwiftUI

struct InkScreen: View {
    let vault: VaultStore
    let relativePath: String
    let isSidebarPresented: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var draft = InkDrawingDraft()
    @State private var activePath: String
    @State private var titleDraft: String
    @State private var isEditingTitle = false
    @State private var isFullscreen = false
    @State private var notebook = InkNotebook()
    @State private var currentPageIndex = 0
    @State private var canvasRevision = 0
    @State private var canvasCommandID = 0
    @State private var canvasCommand: (id: Int, action: InkCanvasCommand)?
    @State private var canUndoDrawing = false
    @State private var canRedoDrawing = false
    @State private var zoomPercent = 100
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var deleteConfirmation = false
    @State private var deletePageIndex: Int?
    @State private var isPageOverviewPresented = false
    @State private var pageUndoStack: [PageHistoryState] = []
    @State private var pageRedoStack: [PageHistoryState] = []
    @FocusState private var isTitleFocused: Bool

    init(vault: VaultStore, relativePath: String, isSidebarPresented: Bool = false) {
        self.vault = vault
        self.relativePath = relativePath
        self.isSidebarPresented = isSidebarPresented
        _activePath = State(initialValue: relativePath)
        _titleDraft = State(initialValue: URL(fileURLWithPath: relativePath)
            .deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsBar
            divider

            InkCanvasView(
                drawing: draft.drawing,
                drawingRevision: canvasRevision,
                paper: currentPaper,
                command: canvasCommand,
                isToolPickerVisible: !isPageOverviewPresented && !isEditingTitle && !isSidebarPresented,
                onDrawingChanged: drawingDidChange
                , onUndoStateChanged: { canUndo, canRedo in
                    canUndoDrawing = canUndo
                    canRedoDrawing = canRedo
                }
                , onZoomChanged: { zoomPercent = $0 }
            )
            .ignoresSafeArea(edges: .bottom)

            divider
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isFullscreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(isFullscreen)
        .task(id: activePath) { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushSave() }
        }
        .onDisappear { flushSave() }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused, isEditingTitle { commitTitle() }
        }
        .confirmationDialog(
            "Delete this page?",
            isPresented: $deleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete page", role: .destructive) {
                deletePage(at: deletePageIndex ?? currentPageIndex)
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
                    onAdd: addPage,
                    onDelete: requestDeletePage,
                    canUndoPages: !pageUndoStack.isEmpty,
                    canRedoPages: !pageRedoStack.isEmpty,
                    onUndoPages: undoPageChange,
                    onRedoPages: redoPageChange
                )
            }
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 0) {
            if horizontalSizeClass == .compact {
                titleControl
                    .frame(maxWidth: 124)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlintSpace.s1) {
                        controlItems
                    }
                        .padding(.horizontal, FlintSpace.s1)
                }

                fullscreenButton
                    .padding(.horizontal, FlintSpace.s1)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlintSpace.s1) {
                        titleControl
                        controlItems
                        fullscreenButton
                    }
                    .padding(.horizontal, FlintSpace.s1)
                }
            }
        }
        .frame(height: 52)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { FlintColor.borderSubtle.frame(height: 1) }
    }

    @ViewBuilder
    private var controlItems: some View {
        pageControls

        Button {
            issue(.undo)
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .disabled(!canUndoDrawing)
        .buttonStyle(.flintIcon)

        Button {
            issue(.redo)
        } label: {
            Image(systemName: "arrow.uturn.forward")
        }
        .disabled(!canRedoDrawing)
        .buttonStyle(.flintIcon)

        Button {
            persistDraftToCurrentPage()
            isPageOverviewPresented = true
        } label: {
            Image(systemName: "square.grid.2x2")
        }
        .buttonStyle(.flintIcon)

        paperMenu
        zoomControls
    }

    private var fullscreenButton: some View {
        Button {
            isFullscreen.toggle()
        } label: {
            Image(systemName: isFullscreen
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.flintIcon)
        .accessibilityLabel(isFullscreen ? "Exit full screen" : "Enter full screen")
    }

    private var titleControl: some View {
        Group {
            if isEditingTitle {
                TextField("Notebook title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit { commitTitle() }
            } else {
                Text(titleDraft)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { startEditingTitle() }
            }
        }
        .frame(minWidth: horizontalSizeClass == .compact ? 104 : 150, maxWidth: 190)
        .padding(.horizontal, FlintSpace.s2)
        .accessibilityHint("Double tap to rename")
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            Button { issue(.zoomOut) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.flintIcon)

            Button { issue(.fit) } label: {
                Text("\(zoomPercent)%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 46, height: 40)
            }
            .buttonStyle(.flintPressable)
            .accessibilityLabel("Fit page")

            Button { issue(.zoomIn) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.flintIcon)
        }
        .background(FlintColor.surfaceRaised, in: Capsule())
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

    private func issue(_ action: InkCanvasCommand) {
        canvasCommandID += 1
        canvasCommand = (canvasCommandID, action)
    }

    private func startEditingTitle() {
        isEditingTitle = true
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func commitTitle() {
        guard isEditingTitle else { return }
        isEditingTitle = false
        isTitleFocused = false
        let newName = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldName = URL(fileURLWithPath: activePath).deletingPathExtension().lastPathComponent
        guard !newName.isEmpty else {
            titleDraft = oldName
            return
        }
        guard newName != oldName,
              let root = vault.rootURL,
              let node = vault.node(at: root.appendingPathComponent(activePath)) else { return }

        Task { @MainActor in
            guard let newURL = await vault.rename(node, to: newName),
                  let newPath = vault.relativePath(for: newURL) else {
                titleDraft = oldName
                return
            }
            activePath = newPath
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
                guard notebook.pages[currentPageIndex].paper != newPaper else { return }
                recordPageChange()
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
        recordPageChange()
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
        recordPageChange()
        notebook.pages.append(.init())
        currentPageIndex = notebook.pages.count - 1
        loadCurrentPageIntoDraft()
        scheduleSave()
    }

    private func requestDeletePage(at index: Int) {
        guard notebook.pages.count > 1, notebook.pages.indices.contains(index) else { return }
        deletePageIndex = index
        deleteConfirmation = true
    }

    private func deletePage(at index: Int) {
        guard notebook.pages.count > 1, notebook.pages.indices.contains(index) else { return }
        persistDraftToCurrentPage()
        recordPageChange()
        let deletedID = notebook.pages[index].id
        let selectedID = currentPageID
        notebook.pages.remove(at: index)
        if selectedID == deletedID {
            currentPageIndex = min(index, notebook.pages.count - 1)
        } else if let selectedID,
                  let newIndex = notebook.pages.firstIndex(where: { $0.id == selectedID }) {
            currentPageIndex = newIndex
        } else {
            currentPageIndex = min(currentPageIndex, notebook.pages.count - 1)
        }
        loadCurrentPageIntoDraft()
        scheduleSave()
    }

    private var currentPageID: UUID? {
        guard notebook.pages.indices.contains(currentPageIndex) else { return nil }
        return notebook.pages[currentPageIndex].id
    }

    private func recordPageChange() {
        pageUndoStack.append(PageHistoryState(pages: notebook.pages, currentPageID: currentPageID))
        pageRedoStack.removeAll()
    }

    private func undoPageChange() {
        guard let previous = pageUndoStack.popLast() else { return }
        pageRedoStack.append(PageHistoryState(pages: notebook.pages, currentPageID: currentPageID))
        restorePageHistory(previous)
    }

    private func redoPageChange() {
        guard let next = pageRedoStack.popLast() else { return }
        pageUndoStack.append(PageHistoryState(pages: notebook.pages, currentPageID: currentPageID))
        restorePageHistory(next)
    }

    private func restorePageHistory(_ state: PageHistoryState) {
        persistDraftToCurrentPage()
        notebook.pages = state.pages.isEmpty ? [InkNotebook.Page()] : state.pages
        if let id = state.currentPageID,
           let index = notebook.pages.firstIndex(where: { $0.id == id }) {
            currentPageIndex = index
        } else {
            currentPageIndex = min(currentPageIndex, notebook.pages.count - 1)
        }
        loadCurrentPageIntoDraft()
        scheduleSave()
    }

    private func load() async {
        do {
            let loaded = try await vault.notebookLoad(activePath)
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
            try await vault.notebookSave(activePath, notebook)
        } catch {
            vault.errorMessage = "Couldn't save notebook: \(error.localizedDescription)"
        }
    }
}

private struct PageHistoryState: Equatable {
    let pages: [InkNotebook.Page]
    let currentPageID: UUID?
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
