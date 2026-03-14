//
//  FieldInputView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI

// MARK: - Field Input View

/// Renders the appropriate SwiftUI control for a given field type.
struct FieldInputView: View {
    @Binding var draft: FieldValueDraft

    var body: some View {
        switch draft.fieldType {
        case .text:    textInput
        case .number:  numberInput
        case .date:    dateInput
        case .boolean: booleanInput
        }
    }

    // MARK: - Type-Specific Inputs

    private var textInput: some View {
        TextField(draft.fieldName, text: $draft.textValue)
#if os(iOS)
            .textInputAutocapitalization(.sentences)
#endif
    }

    private var numberInput: some View {
        TextField(draft.fieldName, text: $draft.numberText)
#if os(iOS)
            .keyboardType(.decimalPad)
#endif
    }

    private var dateInput: some View {
        DatePicker(draft.fieldName, selection: $draft.dateValue, displayedComponents: .date)
    }

    private var booleanInput: some View {
        Toggle(draft.fieldName, isOn: $draft.boolValue)
    }
}

// MARK: - Preview

#Preview {
    Form {
        Section("Text") {
            FieldInputView(draft: .constant(FieldValueDraft(
                fieldName: "Manufacturer", fieldType: .text, sortOrder: 0
            )))
        }
        Section("Number") {
            FieldInputView(draft: .constant(FieldValueDraft(
                fieldName: "Year", fieldType: .number, sortOrder: 1
            )))
        }
        Section("Date") {
            FieldInputView(draft: .constant(FieldValueDraft(
                fieldName: "Acquired", fieldType: .date, sortOrder: 2
            )))
        }
        Section("Boolean") {
            FieldInputView(draft: .constant(FieldValueDraft(
                fieldName: "Assembled", fieldType: .boolean, sortOrder: 3
            )))
        }
    }
}
