//
//  FieldPreviewSheet.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Preview Sheet

/// The preview on its own, for the field types that have nothing to configure.
///
/// Text and Date fields have no options sheet, so without this they'd be the only types a
/// user couldn't see before committing to them. Peer of `NumberOptionsSheet`,
/// `OptionListOptionsSheet`, and `BooleanOptionsSheet`, each of which ends in the same
/// preview section.
struct FieldPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let fieldName: String
    let fieldType: FieldType

    var body: some View {
        NavigationStack {
            Form {
                FieldPreviewSection(name: fieldName, fieldType: fieldType)
            }
            .navigationTitle("Preview")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Text Field") {
    FieldPreviewSheet(fieldName: "Manufacturer", fieldType: .text)
}
