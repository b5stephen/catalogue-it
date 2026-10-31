//
//  FieldInputView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Field Input View

struct FieldInputView: View {
    let label: String
    @Binding var draft: FieldValueDraft

    var body: some View {
        FieldControl(
            label: label,
            fieldType: draft.fieldType,
            numberOptions: draft.fieldDefinition.numberOptions ?? NumberOptions(),
            optionListOptions: draft.fieldDefinition.optionListOptions ?? OptionListOptions(),
            booleanOptions: draft.fieldDefinition.booleanOptions ?? BooleanOptions(),
            booleanIcon: draft.fieldDefinition.showsIconBadge ? draft.fieldDefinition.flagIconName : nil,
            booleanIconColor: draft.fieldDefinition.flagColor,
            textValue: $draft.textValue,
            numberValue: $draft.numberValue,
            dateValue: $draft.dateValue,
            boolValue: $draft.boolValue
        )
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
