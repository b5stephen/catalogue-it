//
//  FieldDefinition.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftData

// MARK: - Field Definition

@Model
final class FieldDefinition {
    // Every stored property below carries a default value: CloudKit rejects
    // non-optional attributes that have none, and the container fails to build.
    var fieldID: UUID = UUID()
    var name: String = ""
    var fieldType: FieldType = FieldType.text
    var priority: Int = 0
    var fieldOptions: FieldOptions? // Only set when the field type has options
    // Fully qualified: `@Model` fails to compile a bare `.none`.
    var displayRole: DisplayRole = DisplayRole.none
    var catalogue: Catalogue?
    // Optional for CloudKit; use the accessor below.
    @Relationship(deleteRule: .nullify, inverse: \FieldValue.fieldDefinition)
    var storedFieldValues: [FieldValue]? = []

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
    /// False for a field whose type changed out from under the role, so the UI shows no tab
    /// bar rather than a broken one.
    var isStatusField: Bool {
        displayRole == .statusTabs && FieldDefinitionValidation.supportsStatusTabs(self)
    }

    var isFlagField: Bool {
        displayRole == .flagFilter && fieldType == .boolean
    }

    var statusTabLabels: (trueLabel: String, falseLabel: String) {
        (booleanOptions ?? BooleanOptions()).resolvedLabels
    }
}

// MARK: - Relationship Accessors

/// Must stay in an extension — see Catalogue.swift.
extension FieldDefinition {
    var fieldValues: [FieldValue] {
        get { storedFieldValues ?? [] }
        set { storedFieldValues = newValue }
    }
}

// MARK: - Ordering

extension FieldDefinition {
    /// Equal priorities (two devices adding a field before a merge) fall back to `fieldID`, so
    /// every device orders the same set the same way.
    nonisolated static func isOrderedBefore(_ a: FieldDefinition, _ b: FieldDefinition) -> Bool {
        if a.priority != b.priority { return a.priority < b.priority }
        return a.fieldID.uuidString < b.fieldID.uuidString
    }
}
