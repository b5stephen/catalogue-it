//
//  ItemDetailSections.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 16/03/2026.
//

import SwiftUI

// MARK: - Item Fields Section

struct ItemFieldsSection: View {
    let fields: [(FieldDefinition, FieldValue)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fields, id: \.0.id) { def, val in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(val.displayValue)
                            .font(.body)
                    }

                    Spacer()
                }
                .padding(.vertical, 10)

                Divider()
            }
        }
    }
}

// MARK: - Item Notes Section

struct ItemNotesSection: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(notes)
                .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.medium))
    }
}
