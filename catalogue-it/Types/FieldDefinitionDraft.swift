//
//  FieldDefinitionDraft.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import Foundation
import SwiftData

// MARK: - Field Definition Draft

struct FieldDefinitionDraft: Identifiable {
    let id: UUID = UUID() // SwiftUI list identity only
    var existingDefinition: FieldDefinition? // nil = new field being added
    var name: String
    var fieldType: FieldType
    var priority: Int
    /// Normalised against the field type by `FieldDefinitionValidation` before save.
    var displayRole: DisplayRole = .none
    var numberOptions: NumberOptions = NumberOptions()
    var optionListOptions: OptionListOptions = OptionListOptions()
    var booleanOptions: BooleanOptions = BooleanOptions()
    /// Original name → current, cascaded to FieldValues on save. A→B then B→C records A→C.
    var pendingOptionRenames: [String: String] = [:]
    var pendingOptionDeletions: Set<String> = []

    /// "Unchanged since loading". Leaves out `id`, which differs per instance, and `priority`,
    /// which the editor renumbers on every drag; the save uses array position instead.
    func hasSameContent(as other: FieldDefinitionDraft) -> Bool {
        existingDefinition === other.existingDefinition
            && name == other.name
            && fieldType == other.fieldType
            && displayRole == other.displayRole
            && numberOptions == other.numberOptions
            && optionListOptions == other.optionListOptions
            && booleanOptions == other.booleanOptions
            && pendingOptionRenames == other.pendingOptionRenames
            && pendingOptionDeletions == other.pendingOptionDeletions
    }
}

extension Array where Element == FieldDefinitionDraft {
    /// Element-wise `hasSameContent(as:)`, so a reorder reads as a change.
    func hasSameContent(as other: [FieldDefinitionDraft]) -> Bool {
        count == other.count && zip(self, other).allSatisfy { $0.hasSameContent(as: $1) }
    }
}

// MARK: - Field Value Draft

struct FieldValueDraft: Identifiable {
    let id: UUID = UUID()
    let fieldDefinition: FieldDefinition
    /// Captured up front: the definition may be deleted on another device while the sheet is
    /// open, and a deleted model's properties are not safe to read.
    let fieldID: UUID
    let fieldType: FieldType

    var textValue: String = ""
    var numberValue: Double? = nil
    var dateValue: Date? = nil
    var boolValue: Bool = false

    init(fieldDefinition: FieldDefinition, fieldType: FieldType) {
        self.fieldDefinition = fieldDefinition
        self.fieldID = fieldDefinition.fieldID
        self.fieldType = fieldType
    }

    /// Compares only the type's own slot, so a stray value in another never reads as an edit.
    func hasSameValue(as other: FieldValueDraft) -> Bool {
        guard fieldType == other.fieldType else { return false }
        switch fieldType {
        case .text, .optionList: return textValue == other.textValue
        case .number: return numberValue == other.numberValue
        case .date: return dateValue == other.dateValue
        case .boolean: return boolValue == other.boolValue
        }
    }
}

// MARK: - Edit Baseline

/// What the edit sheet loaded. A draft equal to it isn't written back, since the stored value
/// may have changed on another device while the sheet was open. See `ItemSaveService`.
struct EditBaseline {
    var fieldDrafts: [FieldValueDraft]
    var photoDrafts: [PhotoDraft]
    var notes: String
}

// MARK: - Photo Draft

struct PhotoDraft: Identifiable, Equatable {
    let id: UUID = UUID()
    var imageData: Data
    var caption: String = ""
    var priority: Int
    /// So saving updates that record rather than re-uploading it. `nil` for a new photo, and
    /// for a duplicated item's, which must become new records.
    var existingPhotoID: PersistentIdentifier? = nil
}
