//
//  FieldDefinitionRow.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Field Definition Row

/// One field in the catalogue form's Custom Fields list. Everything about the field —
/// its name, and whatever its type has to configure — is edited in `FieldEditorView`,
/// reached by tapping the row or by its Edit swipe action. The row itself is display
/// only, so every field reads the same however it is typed.
///
/// While the list is in reorder mode the row goes inert: iOS suppresses swipe actions in
/// edit mode anyway, and a tap there belongs to the drag handle, not to the editor.
struct FieldDefinitionRow: View {
    @Binding var field: FieldDefinitionDraft
    /// Names of the other fields in the catalogue, for the editor's duplicate check.
    var otherFieldNames: [String] = []
    /// Routed back to the parent, which owns the "this field holds data" confirmation.
    var onDelete: () -> Void

#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @State private var showingEditor = false

    /// macOS has no edit mode, so the list is never in the reordering state there.
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
        // Swiping is a trackpad-only gesture on macOS, so the same two actions get a
        // context menu — the pattern the catalogue list already uses.
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
