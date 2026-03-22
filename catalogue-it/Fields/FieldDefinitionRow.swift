//
//  FieldDefinitionRow.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Field Definition Row

struct FieldDefinitionRow: View {
    @Binding var field: FieldDefinitionDraft
    @State private var showingPrecisionSettings = false

    var body: some View {
        HStack(spacing: 12) {
            TextField("Field Name", text: $field.name)
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
            Spacer()
            if field.fieldType == .number || field.fieldType == .currency {
                Button {
                    showingPrecisionSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(field.fieldType.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingPrecisionSettings) {
            PrecisionSettingsSheet(precision: field.precision) { newPrecision in
                field.precision = newPrecision
            }
        }
    }
}
