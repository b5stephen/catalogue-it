//
//  FieldControl.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Control

/// Driven by plain values rather than a `FieldDefinition`, so field-configuration previews of
/// an unsaved draft render the real control.
struct FieldControl: View {
    let label: String
    let fieldType: FieldType
    var numberOptions: NumberOptions = NumberOptions()
    var optionListOptions: OptionListOptions = OptionListOptions()
    var booleanOptions: BooleanOptions = BooleanOptions()
    /// Set only where the field shows its icon (`showsIconBadge`); `nil` keeps the switch.
    var booleanIcon: String? = nil
    var booleanIconColor: Color? = nil

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
            TextField(
                label,
                value: $numberValue,
                format: .number.grouping(numberOptions.usesGroupingSeparator ? .automatic : .never)
            )
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

    @ViewBuilder
    private var booleanInput: some View {
        if let booleanIcon {
            Toggle(label, isOn: $boolValue)
                .toggleStyle(IconToggleStyle(icon: booleanIcon, color: booleanIconColor, options: booleanOptions))
        } else {
            Toggle(label, isOn: $boolValue)
        }
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
