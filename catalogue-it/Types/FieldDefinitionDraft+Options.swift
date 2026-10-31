//
//  FieldDefinitionDraft+Options.swift
//  catalogue-it
//

import Foundation

// MARK: - Option Edits

extension FieldDefinitionDraft {
    /// Chains collapse (A→B then B→C records A→C), so the cascade only looks for stored names.
    /// A field that hasn't been saved has no stored values, so it records nothing.
    mutating func renameOption(_ old: String, to new: String) {
        if let index = optionListOptions.options.firstIndex(of: old) {
            optionListOptions.options[index] = new
        }
        if optionListOptions.defaultValue == old {
            optionListOptions.defaultValue = new
        }
        guard new != old, existingDefinition != nil else { return }
        if let originalName = pendingOptionRenames.first(where: { $0.value == old })?.key {
            pendingOptionRenames[originalName] = new
        } else {
            pendingOptionRenames[old] = new
        }
    }

    mutating func deleteOption(_ option: String) {
        optionListOptions.options.removeAll { $0 == option }
        if optionListOptions.defaultValue == option {
            optionListOptions.defaultValue = nil
        }
        guard existingDefinition != nil else { return }
        // Stored values still carry the original name, so delete by that.
        if let originalName = pendingOptionRenames.first(where: { $0.value == option })?.key {
            pendingOptionRenames.removeValue(forKey: originalName)
            pendingOptionDeletions.insert(originalName)
        } else {
            pendingOptionDeletions.insert(option)
        }
    }
}
