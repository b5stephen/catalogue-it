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
/// so every row carries the same single pencil button rather than a different control
/// per field type.
struct FieldDefinitionRow: View {
    @Binding var field: FieldDefinitionDraft
    /// Names of the other fields in the catalogue, for the editor's duplicate check.
    var otherFieldNames: [String] = []

    @State private var showingEditor = false

    private var displayName: String {
        let trimmed = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Field") : trimmed
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .foregroundStyle(field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Text(field.fieldType.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                showingEditor = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(displayName)")
        }
        .sheet(isPresented: $showingEditor) {
            FieldEditorView(editing: field, existingNames: otherFieldNames) { edited in
                field = edited
            }
        }
    }
}
