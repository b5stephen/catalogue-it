//
//  ItemDetailSections.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 16/03/2026.
//

import SwiftUI

// MARK: - Field Row

private struct FieldRowView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.body)
                }
                Spacer()
            }
            .padding(.vertical, 10)

            Divider()
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                copyToClipboard(value)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

private func copyToClipboard(_ string: String) {
#if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
#else
    UIPasteboard.general.string = string
#endif
}

// MARK: - Item Fields Section

struct ItemFieldsSection: View {
    let fields: [(FieldDefinition, FieldValue)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fields, id: \.0.id) { def, val in
                if def.isStatusField {
                    // The status field gets the same chip treatment as the item row, and
                    // resolves boolean statuses through their tab labels rather than showing
                    // a bare "Yes"/"No" that doesn't match what the tab bar says.
                    StatusFieldRowView(field: def, value: val)
                } else {
                    FieldRowView(label: def.name, value: val.displayValue(options: def.fieldOptions))
                }
            }
        }
    }
}

// MARK: - Status Field Row

private struct StatusFieldRowView: View {
    let field: FieldDefinition
    let value: FieldValue

    /// Recomputed from the field value rather than read from `CatalogueItem.statusValue`,
    /// so the detail view shows what is actually stored on the item.
    private var storedValue: String {
        ItemFacetBuilder.statusValue(from: [value], definitions: [field])
    }

    var body: some View {
        HStack {
            Text(field.name)
                .foregroundStyle(.secondary)
            Spacer()
            if let label = field.statusLabel(for: storedValue) {
                FieldChipView(text: label, tint: field.statusChipTint(for: storedValue))
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Item Notes Section

struct ItemNotesSection: View {
    let notes: String

    var body: some View {
        FieldRowView(label: "Notes", value: notes)
    }
}
