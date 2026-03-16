//
//  FieldDefinitionRow.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Field Definition Row

struct FieldDefinitionRow: View {
    let field: FieldDefinitionDraft
    var isDisplayField: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: field.fieldType.icon)
                .foregroundStyle(field.fieldType.color)
                .frame(width: 24)

            Text(field.name)

            Spacer()

            if isDisplayField {
                Text("Display Name")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15))
                    .foregroundStyle(.tint)
                    .clipShape(Capsule())
            }

            Text(field.fieldType.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
