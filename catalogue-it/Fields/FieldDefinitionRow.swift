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

    private var displayName: String {
        let trimmed = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Field") : trimmed
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .foregroundStyle(isUnnamed ? .secondary : .primary)
                    .lineLimit(1)
                Text(field.fieldType.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
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
        .accessibilityLabel("\(displayName), \(field.fieldType.rawValue)")
        .accessibilityHint("Opens the field editor")
        .sheet(isPresented: $showingEditor) {
            FieldEditorView(editing: field, existingNames: otherFieldNames) { edited in
                field = edited
            }
        }
    }
}
