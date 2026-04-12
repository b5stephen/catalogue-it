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
    @State private var showingNumberOptions = false
    @State private var showingOptionListOptions = false

    var body: some View {
        HStack(spacing: 12) {
            TextField("Field Name", text: $field.name)
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
            Spacer()
            if field.fieldType == .number {
                Button {
                    showingNumberOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if field.fieldType == .optionList {
                Button {
                    showingOptionListOptions = true
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(field.fieldType.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingNumberOptions) {
            NumberOptionsSheet(options: field.numberOptions) { newOptions in
                field.numberOptions = newOptions
            }
        }
        .sheet(isPresented: $showingOptionListOptions) {
            OptionListOptionsSheet(options: field.optionListOptions, onSave: { newOptions in
                field.optionListOptions = newOptions
            }, onRename: { old, new in
                // Handle chains: if old was already a rename target, update the source's mapping
                if let originalName = field.pendingOptionRenames.first(where: { $0.value == old })?.key {
                    field.pendingOptionRenames[originalName] = new
                } else {
                    field.pendingOptionRenames[old] = new
                }
            }, onDelete: { deleted in
                // If a pending rename pointed to this option, remove it (no cascade needed)
                if let originalName = field.pendingOptionRenames.first(where: { $0.value == deleted })?.key {
                    field.pendingOptionRenames.removeValue(forKey: originalName)
                }
                field.pendingOptionDeletions.insert(deleted)
            })
        }
    }
}
