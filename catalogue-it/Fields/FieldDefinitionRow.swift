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
    @State private var showingBooleanOptions = false

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
            // Labels and appearance, available on every Yes/No field. The role that uses
            // them is chosen in the catalogue's Options section, not here.
            if field.fieldType == .boolean {
                Button {
                    showingBooleanOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Yes/No Options")
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
        .sheet(isPresented: $showingBooleanOptions) {
            BooleanOptionsSheet(options: field.booleanOptions) { newOptions in
                field.booleanOptions = newOptions
            }
        }
        .sheet(isPresented: $showingOptionListOptions) {
            OptionListOptionsSheet(options: field.optionListOptions, onSave: { newOptions in
                field.optionListOptions = newOptions
                // Dropping below the two-option minimum makes a tab bar impossible; give up
                // the role here so the Options section stops showing this field as the
                // status field, rather than letting the save silently discard it.
                if field.displayRole == .statusTabs,
                   newOptions.options.count < FieldDefinitionValidation.minimumStatusOptions {
                    field.displayRole = .none
                }
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
