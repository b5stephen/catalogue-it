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
    /// Name of another field currently driving the tab bar, surfaced as a warning in the
    /// display sheet. `nil` when this field is the only claimant, or there is none.
    var otherStatusFieldName: String? = nil
    /// Called when this field takes the `.statusTabs` role, so the owner can demote the
    /// previous holder — only one tab bar exists per catalogue.
    var onClaimStatusRole: () -> Void = {}
    /// Catalogue-level "All" tab setting, edited alongside the status role that gives it meaning.
    @Binding var showAllTab: Bool

    @State private var showingNumberOptions = false
    @State private var showingOptionListOptions = false
    @State private var showingDisplayOptions = false

    /// Whether this field's type can carry a display role at all.
    private var supportsDisplayRole: Bool {
        field.fieldType == .boolean || field.fieldType == .optionList
    }

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
            // Any boolean or option-list field can be promoted to the tab bar or a filter
            // toggle here — presets are a shortcut for creating one, not the only route.
            if supportsDisplayRole {
                Button {
                    showingDisplayOptions = true
                } label: {
                    Image(systemName: field.displayRole == .none ? "eye" : "eye.fill")
                        .foregroundStyle(field.displayRole == .none ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Display Options")
            }
            // Names the role at a glance, so a field driving the tab bar or a filter doesn't
            // look like an ordinary one in the list.
            if field.displayRole != .none {
                Text(field.displayRole.label)
                    .font(.caption2)
                    .foregroundStyle(.tint)
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
        .sheet(isPresented: $showingDisplayOptions) {
            FieldDisplayOptionsSheet(
                fieldType: field.fieldType,
                fieldName: field.name,
                optionCount: field.optionListOptions.options.count,
                otherStatusFieldName: otherStatusFieldName,
                displayRole: field.displayRole,
                booleanOptions: field.booleanOptions,
                showAllTab: showAllTab
            ) { newRole, newBooleanOptions, newShowAllTab in
                field.displayRole = newRole
                field.booleanOptions = newBooleanOptions
                showAllTab = newShowAllTab
                if newRole == .statusTabs { onClaimStatusRole() }
            }
        }
        .sheet(isPresented: $showingOptionListOptions) {
            OptionListOptionsSheet(options: field.optionListOptions, onSave: { newOptions in
                field.optionListOptions = newOptions
                // Dropping below the two-option minimum makes a tab bar impossible; reset
                // the role here rather than letting the save silently discard it.
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
