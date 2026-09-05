//
//  BooleanOptionsSheet.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Boolean Options Sheet

/// Edits an existing Yes/No field's labels and appearance.
///
/// Reached from `FieldDefinitionRow` for every `.boolean` field, whatever its display role —
/// the peer of `NumberOptionsSheet` and `OptionListOptionsSheet`.
struct BooleanOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Only used to label the preview, so it reads as the field being edited.
    let fieldName: String
    /// Shapes the preview's display line — a status field shows a chip, a flag its badge.
    let displayRole: DisplayRole

    @State private var options: BooleanOptions
    let onSave: (BooleanOptions) -> Void

    init(fieldName: String, displayRole: DisplayRole = .none, options: BooleanOptions, onSave: @escaping (BooleanOptions) -> Void) {
        self.fieldName = fieldName
        self.displayRole = displayRole
        self._options = State(initialValue: options)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                BooleanOptionsSection(options: $options)

                FieldPreviewSection(
                    name: fieldName,
                    fieldType: .boolean,
                    booleanOptions: options,
                    displayRole: displayRole
                )
            }
            .navigationTitle("Yes/No Options")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(options)
                        dismiss()
                    }
                }
            }
        }
    }
}
