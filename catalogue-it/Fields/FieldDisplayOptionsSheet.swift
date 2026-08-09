//
//  FieldDisplayOptionsSheet.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Display Options Sheet

/// Edits how an existing field is surfaced in the item list.
///
/// Reached from `FieldDefinitionRow` for any `.boolean` or `.optionList` field, so a field
/// created as an ordinary one can be promoted to the tab bar or a filter toggle later —
/// and demoted again — without deleting and recreating it.
struct FieldDisplayOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let fieldType: FieldType
    let fieldName: String
    let optionCount: Int
    let otherStatusFieldName: String?

    @State private var displayRole: DisplayRole
    @State private var booleanOptions: BooleanOptions
    @State private var showAllTab: Bool
    let onSave: (DisplayRole, BooleanOptions, Bool) -> Void

    init(
        fieldType: FieldType,
        fieldName: String,
        optionCount: Int,
        otherStatusFieldName: String?,
        displayRole: DisplayRole,
        booleanOptions: BooleanOptions,
        showAllTab: Bool,
        onSave: @escaping (DisplayRole, BooleanOptions, Bool) -> Void
    ) {
        self.fieldType = fieldType
        self.fieldName = fieldName
        self.optionCount = optionCount
        self.otherStatusFieldName = otherStatusFieldName
        self._displayRole = State(initialValue: displayRole)
        self._booleanOptions = State(initialValue: booleanOptions)
        self._showAllTab = State(initialValue: showAllTab)
        self.onSave = onSave
    }

    /// A tab bar backed by an option list needs enough options to be meaningful. Blocking
    /// Done here keeps the user from a silent reset on save.
    private var canSave: Bool {
        FieldDefinitionValidation.supports(
            role: displayRole,
            fieldType: fieldType,
            optionCount: optionCount
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                FieldDisplayOptionsSection(
                    fieldType: fieldType,
                    fieldName: fieldName,
                    optionCount: optionCount,
                    otherStatusFieldName: otherStatusFieldName,
                    displayRole: $displayRole,
                    booleanOptions: $booleanOptions,
                    showAllTab: $showAllTab
                )
            }
            .navigationTitle("Display Options")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(displayRole, booleanOptions, showAllTab)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
