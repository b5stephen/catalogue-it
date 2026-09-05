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

    @State private var options: BooleanOptions
    let onSave: (BooleanOptions) -> Void

    init(options: BooleanOptions, onSave: @escaping (BooleanOptions) -> Void) {
        self._options = State(initialValue: options)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                BooleanOptionsSection(options: $options)
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
