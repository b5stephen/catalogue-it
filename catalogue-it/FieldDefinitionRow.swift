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

    var body: some View {
        HStack(spacing: 12) {
            Text(field.name)
            Spacer()
            Text(field.fieldType.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
