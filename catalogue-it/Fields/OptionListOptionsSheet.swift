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
    let onRename: ((String, String) -> Void)?
    let onDelete: ((String) -> Void)?

    @State private var options: [String]
    @State private var defaultValue: String?
    @State private var newOptionText: String = ""
    @State private var renamingOption: String? = nil
    @State private var renameText: String = ""

    init(options: OptionListOptions?, onSave: @escaping (OptionListOptions) -> Void, onRename: ((String, String) -> Void)? = nil, onDelete: ((String) -> Void)? = nil) {
        self.onSave = onSave
        self.onRename = onRename
        self.onDelete = onDelete
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
                        .swipeActions(edge: .leading) {
                            Button {
                                renamingOption = option
                                renameText = option
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if defaultValue == option { defaultValue = nil }
                                options.removeAll { $0 == option }
                                onDelete?(option)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
            .alert("Rename Option", isPresented: Binding(get: { renamingOption != nil }, set: { if !$0 { renamingOption = nil } })) {
                TextField("Option name", text: $renameText)
#if os(iOS)
                    .textInputAutocapitalization(.words)
#endif
                Button("Cancel", role: .cancel) { renamingOption = nil }
                Button("Rename") {
                    if let old = renamingOption {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, !options.contains(trimmed) || trimmed == old else { return }
                        if let idx = options.firstIndex(of: old) { options[idx] = trimmed }
                        if defaultValue == old { defaultValue = trimmed }
                        if trimmed != old { onRename?(old, trimmed) }
                        renamingOption = nil
                    }
                }
            } message: {
                Text("Enter a new name for \"\(renamingOption ?? "")\".")
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
