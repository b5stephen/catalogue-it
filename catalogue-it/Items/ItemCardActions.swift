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
    /// `shape` is the card's, so the lifted preview keeps its corners. Off, the menu is empty
    /// and the system shows none.
    func itemCardContextMenu(
        _ item: CatalogueItem,
        actions: ItemCardActions,
        shape: RoundedRectangle,
        isEnabled: Bool = true
    ) -> some View {
        contentShape(.contextMenuPreview, shape)
            .contextMenu {
                if isEnabled {
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
    }

    /// Edit is outermost, so a full swipe edits and never deletes.
    func itemCardSwipeActions(_ item: CatalogueItem, actions: ItemCardActions, isEnabled: Bool = true) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isEnabled {
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

// MARK: - Selection Check

/// The mark select mode puts on a card, filled in the catalogue's tint once picked.
struct SelectionCheck: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(isSelected ? .palette : .monochrome)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary), .tint)
            .background(.background, in: .circle)
            .accessibilityHidden(true)
    }
}
