import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct InkPageOverview: View {
    @Binding var pages: [InkNotebook.Page]
    let currentIndex: Int
    var onSelect: (Int) -> Void
    var onReorder: (IndexSet, Int) -> Void
    var onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draggingID: UUID?

    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 180), spacing: FlintSpace.s3)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: FlintSpace.s3) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        onSelect(index)
                        dismiss()
                    } label: {
                        PageThumbnail(
                            page: page,
                            index: index,
                            isCurrent: index == currentIndex,
                            isDragging: draggingID == page.id
                        )
                    }
                    .buttonStyle(.plain)
                    .onDrag {
                        draggingID = page.id
                        return NSItemProvider(object: page.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: PageDropDelegate(
                            target: page,
                            pages: $pages,
                            draggingID: $draggingID,
                            onReorder: onReorder
                        )
                    )
                }
            }
            .padding(FlintSpace.s4)
        }
        .background(FlintColor.bg)
        .navigationTitle("Pages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

private struct PageThumbnail: View {
    let page: InkNotebook.Page
    let index: Int
    let isCurrent: Bool
    let isDragging: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: FlintSpace.s2) {
            ZStack {
                FlintColor.surfaceRaised
                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "doc")
                        .font(.title2)
                        .foregroundStyle(FlintColor.textMuted)
                }
            }
            .aspectRatio(0.75, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: FlintRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FlintRadius.sm, style: .continuous)
                    .stroke(isCurrent ? FlintColor.accent : FlintColor.border, lineWidth: isCurrent ? 2 : 1)
            )

            Text("Page \(index + 1)")
                .font(.caption)
                .foregroundStyle(isCurrent ? FlintColor.textPrimary : FlintColor.textSecondary)
                .lineLimit(1)
        }
        .opacity(isDragging ? 0.45 : 1)
        .contentShape(Rectangle())
    }

    private var thumbnail: UIImage? {
        guard let data = try? InkRenderer.pagePNG(
            page,
            maxSize: CGSize(width: 180, height: 240),
            scale: displayScale
        ) else { return nil }
        return UIImage(data: data)
    }
}

private struct PageDropDelegate: DropDelegate {
    let target: InkNotebook.Page
    @Binding var pages: [InkNotebook.Page]
    @Binding var draggingID: UUID?
    var onReorder: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != target.id,
              let from = pages.firstIndex(where: { $0.id == draggingID }),
              let to = pages.firstIndex(where: { $0.id == target.id }) else { return }

        withAnimation(.easeOut(duration: FlintMotion.fast)) {
            onReorder(IndexSet(integer: from), from < to ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}
