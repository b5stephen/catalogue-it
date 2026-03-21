//
//  FieldInputView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Field Input View

/// Renders the appropriate SwiftUI control for a given field type.
struct FieldInputView: View {
    let label: String
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
        TextField(label, text: $draft.textValue)
#if os(iOS)
            .textInputAutocapitalization(.sentences)
#endif
    }

    private var numberInput: some View {
        TextField(label, value: $draft.numberValue, format: .number)
#if os(iOS)
            .keyboardType(.decimalPad)
#endif
    }

    @ViewBuilder
    private var dateInput: some View {
        if draft.dateValue == nil {
            Button("Set \(label)") { draft.dateValue = .now }
        } else {
            HStack {
                DatePicker(
                    label,
                    selection: Binding(
                        get: { draft.dateValue ?? .now },
                        set: { draft.dateValue = $0 }
                    ),
                    displayedComponents: .date
                )
                Button { draft.dateValue = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var booleanInput: some View {
        Toggle(label, isOn: $draft.boolValue)
    }
}

// MARK: - Preview

#Preview {
    // Previews require a model container since FieldValueDraft now holds a FieldDefinition
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FieldDefinition.self, configurations: config)
    let def = FieldDefinition(name: "Example", fieldType: .text)
    container.mainContext.insert(def)

    return Form {
        Section("Text") {
            FieldInputView(label: "Manufacturer", draft: .constant(FieldValueDraft(fieldDefinition: def, fieldType: .text)))
        }
        Section("Number") {
            FieldInputView(label: "Year", draft: .constant(FieldValueDraft(fieldDefinition: def, fieldType: .number)))
        }
        Section("Date") {
            FieldInputView(label: "Acquired", draft: .constant(FieldValueDraft(fieldDefinition: def, fieldType: .date)))
        }
        Section("Boolean") {
            FieldInputView(label: "Assembled", draft: .constant(FieldValueDraft(fieldDefinition: def, fieldType: .boolean)))
        }
    }
    .modelContainer(container)
}
