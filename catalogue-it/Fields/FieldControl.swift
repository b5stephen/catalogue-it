//
//  FieldControl.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Control

/// The editing control for a single field, driven by plain values rather than by a
/// persisted `FieldDefinition`.
///
/// The item form reaches it through `FieldInputView`; the field-configuration previews
/// render it directly from an unsaved draft. Both go through this one view so a preview
/// is the control the user will actually get, not a lookalike.
struct FieldControl: View {
    let label: String
    let fieldType: FieldType
    var numberOptions: NumberOptions = NumberOptions()
    var optionListOptions: OptionListOptions = OptionListOptions()

    @Binding var textValue: String
    @Binding var numberValue: Double?
    @Binding var dateValue: Date?
    @Binding var boolValue: Bool

    var body: some View {
        switch fieldType {
        case .text:       textInput
        case .number:     numberInput
        case .date:       dateInput
        case .boolean:    booleanInput
        case .optionList: optionListInput
        }
    }

    // MARK: - Type-Specific Inputs

    private var textInput: some View {
        TextField(label, text: $textValue)
#if os(iOS)
            .textInputAutocapitalization(.sentences)
#endif
    }

    private var numberInput: some View {
        HStack(spacing: 4) {
            if numberOptions.format == .currency {
                Text(Locale.current.currencySymbol ?? "$")
                    .foregroundStyle(.secondary)
            }
            TextField(label, value: $numberValue, format: .number)
#if os(iOS)
                .keyboardType(numberOptions.precision == 0 ? .numberPad : .decimalPad)
#endif
        }
    }

    @ViewBuilder
    private var dateInput: some View {
        if dateValue == nil {
            Button("Set \(label)") { dateValue = .now }
        } else {
            HStack {
                DatePicker(
                    label,
                    selection: Binding(
                        get: { dateValue ?? .now },
                        set: { dateValue = $0 }
                    ),
                    displayedComponents: .date
                )
                Button { dateValue = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var booleanInput: some View {
        Toggle(label, isOn: $boolValue)
    }

    private var optionListInput: some View {
        let sorted = optionListOptions.options.sorted()
        let isStale = !textValue.isEmpty && !optionListOptions.options.contains(textValue)
        return Picker(label, selection: $textValue) {
            Text("None").tag("")
            ForEach(sorted, id: \.self) { option in
                Text(option).tag(option)
            }
            if isStale {
                Text("\(textValue) (removed)").tag(textValue)
            }
        }
        .pickerStyle(.menu)
    }
}
