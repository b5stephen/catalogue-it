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
    }
}

// MARK: - Item Fields Section

struct ItemFieldsSection: View {
    let fields: [(FieldDefinition, FieldValue)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fields, id: \.0.id) { def, val in
                FieldRowView(label: def.name, value: val.displayValue(options: def.fieldOptions))
            }
        }
    }
}

// MARK: - Item Notes Section

struct ItemNotesSection: View {
    let notes: String

    var body: some View {
        FieldRowView(label: "Notes", value: notes)
    }
}
