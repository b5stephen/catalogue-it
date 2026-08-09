//
//  FieldDefinition.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData

// MARK: - Field Definition

/// Defines a custom field that exists in a catalogue (e.g., "Year" as a Number field)
@Model
final class FieldDefinition {
    var fieldID: UUID // Stable identifier used for AppStorage-persisted sort preferences
    var name: String
    var fieldType: FieldType
    var priority: Int // For ordering fields in the UI
    var fieldOptions: FieldOptions? // Type-specific configuration; only set when the field type has options
    /// How this field is additionally surfaced in the item list (tab bar / filter toggle).
    /// `.none` for ordinary fields, which is every field unless the user opts in.
    // Fully-qualified default is required by the @Model macro — `.none` alone fails to compile.
    var displayRole: DisplayRole = DisplayRole.none
    var catalogue: Catalogue?
    @Relationship(deleteRule: .nullify, inverse: \FieldValue.fieldDefinition)
    var fieldValues: [FieldValue] = []

    init(
        name: String,
        fieldType: FieldType,
        priority: Int = 0,
        fieldID: UUID = UUID(),
        displayRole: DisplayRole = .none
    ) {
        self.fieldID = fieldID
        self.name = name
        self.fieldType = fieldType
        self.priority = priority
        self.displayRole = displayRole
    }

    /// Convenience accessor for Number field options.
    /// Returns `nil` for non-number fields; callers should handle the optional explicitly.
    var numberOptions: NumberOptions? {
        get {
            if case .number(let opts) = fieldOptions { return opts }
            return nil
        }
        set {
            guard fieldType == .number else { return }
            fieldOptions = newValue.map { .number($0) }
        }
    }

    /// Convenience accessor for Option List field options.
    /// Returns `nil` for non-optionList fields; callers should handle the optional explicitly.
    var optionListOptions: OptionListOptions? {
        get {
            if case .optionList(let opts) = fieldOptions { return opts }
            return nil
        }
        set {
            guard fieldType == .optionList else { return }
            fieldOptions = newValue.map { .optionList($0) }
        }
    }

    /// Convenience accessor for Yes/No field options.
    /// Returns `nil` for non-boolean fields; callers should handle the optional explicitly.
    var booleanOptions: BooleanOptions? {
        get {
            if case .boolean(let opts) = fieldOptions { return opts }
            return nil
        }
        set {
            guard fieldType == .boolean else { return }
            fieldOptions = newValue.map { .boolean($0) }
        }
    }
}

// MARK: - Display Role

extension FieldDefinition {
    /// True when this field both claims the `.statusTabs` role and satisfies its
    /// requirements. A field whose type was changed out from under the role reads as
    /// `false` here, so the UI degrades to "no tab bar" rather than rendering a broken one.
    var isStatusField: Bool {
        displayRole == .statusTabs && FieldDefinitionValidation.supportsStatusTabs(self)
    }

    /// True when this field both claims the `.flagFilter` role and satisfies its requirements.
    var isFlagField: Bool {
        displayRole == .flagFilter && fieldType == .boolean
    }

    /// Tab labels for a `.boolean`-backed status field, falling back to the field name
    /// and "Other" when the user hasn't named them.
    var statusTabLabels: (trueLabel: String, falseLabel: String) {
        let opts = booleanOptions
        let trueLabel = opts?.trueLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let falseLabel = opts?.falseLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            trueLabel: (trueLabel?.isEmpty == false ? trueLabel! : name),
            falseLabel: (falseLabel?.isEmpty == false ? falseLabel! : String(localized: "Other"))
        )
    }
}
