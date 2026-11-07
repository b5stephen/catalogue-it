//
//  ItemCardActions.swift
//  catalogue-it
//

import SwiftUI

/// What a card in the item list or grid offers besides opening the item.
struct ItemCardActions {
    let edit: (CatalogueItem) -> Void
    let duplicate: (CatalogueItem) -> Void
    let share: (CatalogueItem) -> Void
    let delete: (CatalogueItem) -> Void

    static let none = ItemCardActions(edit: { _ in }, duplicate: { _ in }, share: { _ in }, delete: { _ in })
}

extension View {
    /// `shape` is the card's, so the lifted preview keeps its corners.
    func itemCardContextMenu(
        _ item: CatalogueItem,
        actions: ItemCardActions,
        shape: RoundedRectangle
    ) -> some View {
        contentShape(.contextMenuPreview, shape)
            .contextMenu {
                Button {
                    actions.edit(item)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    actions.duplicate(item)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    actions.share(item)
                } label: {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    actions.delete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    /// Edit is outermost, so a full swipe edits and never deletes.
    func itemCardSwipeActions(_ item: CatalogueItem, actions: ItemCardActions) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                actions.edit(item)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            // Not `role: .destructive`, which removes the row itself; the list drops it once the
            // soft delete is saved, and puts it back on Undo.
            Button {
                actions.delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }
}

// MARK: - Undo Toast

struct ItemDeletedToast: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Label("Moved to Recently Deleted", systemImage: "trash")
                .font(.subheadline)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
