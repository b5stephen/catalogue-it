//
//  PrecisionSettingsSheet.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 22/03/2026.
//

import SwiftUI

// MARK: - Precision Settings Sheet

/// A sheet for configuring the decimal precision of a Number or Currency field.
struct PrecisionSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Int) -> Void

    @State private var precision: Int

    init(precision: Int, onSave: @escaping (Int) -> Void) {
        self.onSave = onSave
        _precision = State(initialValue: precision)
    }

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Number Precision")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(precision)
                        dismiss()
                    }
                }
            }
        }
    }
}
