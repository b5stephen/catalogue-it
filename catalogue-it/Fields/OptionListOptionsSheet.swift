//
//  OptionListOptionsSheet.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 12/04/2026.
//

import SwiftUI

// MARK: - Option List Options Sheet

/// A sheet for managing the available options and optional default for an Option List field.
struct OptionListOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (OptionListOptions) -> Void

    @State private var options: [String]
    @State private var defaultValue: String?
    @State private var newOptionText: String = ""

    init(options: OptionListOptions?, onSave: @escaping (OptionListOptions) -> Void) {
        self.onSave = onSave
        _options = State(initialValue: options?.options ?? [])
        _defaultValue = State(initialValue: options?.defaultValue)
    }

    // Options sorted alphabetically for display
    private var sortedOptions: [String] { options.sorted() }

    // Trimmed candidate for the new option being typed
    private var trimmedNew: String { newOptionText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { !trimmedNew.isEmpty && !options.contains(trimmedNew) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(sortedOptions, id: \.self) { option in
                        HStack {
                            Text(option)
                            Spacer()
                            if option == defaultValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            defaultValue = (defaultValue == option) ? nil : option
                        }
                    }
                    .onDelete { offsets in
                        let toRemove = Set(offsets.map { sortedOptions[$0] })
                        if let d = defaultValue, toRemove.contains(d) { defaultValue = nil }
                        options.removeAll { toRemove.contains($0) }
                    }

                    HStack {
                        TextField("New option", text: $newOptionText)
#if os(iOS)
                            .textInputAutocapitalization(.words)
#endif
                        Button {
                            options.append(trimmedNew)
                            newOptionText = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAdd)
                    }
                } header: {
                    Text("Options")
                } footer: {
                    Text("Tap an option to set it as the default. Tap again to clear.")
                }

                if defaultValue != nil {
                    Section {
                        Button("Clear Default", role: .destructive) {
                            defaultValue = nil
                        }
                    }
                }
            }
            .navigationTitle("Option List")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(OptionListOptions(options: options, defaultValue: defaultValue))
                        dismiss()
                    }
                }
            }
        }
    }
}
