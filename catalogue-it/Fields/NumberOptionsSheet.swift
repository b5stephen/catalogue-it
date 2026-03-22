//
//  NumberOptionsSheet.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 22/03/2026.
//

import SwiftUI

// MARK: - Number Options Sheet

/// A sheet for configuring the format and decimal precision of a Number field.
struct NumberOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (NumberOptions) -> Void

    @State private var numberFormat: NumberFormat
    @State private var precision: Int

    init(options: NumberOptions, onSave: @escaping (NumberOptions) -> Void) {
        self.onSave = onSave
        _numberFormat = State(initialValue: options.format)
        _precision = State(initialValue: options.precision)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Format", selection: $numberFormat) {
                        ForEach(NumberFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Decimal Places") {
                    Picker("Decimal Places", selection: $precision) {
                        Text("0 (Whole numbers)").tag(0)
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Number Options")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(NumberOptions(format: numberFormat, precision: precision))
                        dismiss()
                    }
                }
            }
        }
    }
}
