//
//  FieldDefinitionRow.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Field Definition Row

/// Inert while reordering: a tap then belongs to the drag handle, not the editor.
struct FieldDefinitionRow: View {
    @Binding var field: FieldDefinitionDraft
    var otherFieldNames: [String] = []
    var previewContext = FieldPreviewContext()
    /// The parent owns the "this field holds data" confirmation.
    var onDelete: () -> Void

#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @State private var showingEditor = false

    private var isReordering: Bool {
#if os(iOS)
        editMode?.wrappedValue.isEditing == true
#else
        false
#endif
    }

    private var isUnnamed: Bool {
        field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayName: String { field.displayName }

    private var roleBadge: FieldBadge? {
        switch field.displayRole {
        case .none:
            nil
        case .statusTabs:
            FieldBadge(title: String(localized: "Tab Bar"), systemImage: nil, tint: .blue)
        case .flagFilter:
            // Plain: the icon, when there is one, is already the tile.
            FieldBadge(title: String(localized: "Filter"), systemImage: nil, tint: .orange)
        }
    }

    private var badges: [FieldBadge] {
        roleBadge.map { [$0] } ?? []
    }

    private var accessibilitySummary: String {
        ([displayName] + badges.map(\.title) + [field.summary]).joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            FieldTypeTile(symbol: field.tileSymbol, color: field.fieldType.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .foregroundStyle(isUnnamed ? .secondary : .primary)
                    .lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    ForEach(field.summaryVariants, id: \.self) { variant in
                        Text(variant)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ForEach(badges, id: \.title) { badge in
                badge
            }
            // The drag handle takes this slot while reordering.
            if !isReordering {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isReordering else { return }
            showingEditor = true
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                showingEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
#if os(macOS)
        // Swiping is trackpad-only on macOS.
        .contextMenu {
            Button {
                showingEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
#endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens the field editor")
        .sheet(isPresented: $showingEditor) {
            FieldEditorView(editing: field, existingNames: otherFieldNames, previewContext: previewContext) { edited in
                field = edited
            }
        }
    }
}
