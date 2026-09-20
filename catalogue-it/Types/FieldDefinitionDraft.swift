//
//  FieldDefinitionDraft.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import Foundation
import SwiftData

// MARK: - Field Definition Draft

/// A lightweight, non-persisted representation of a field definition used during catalogue editing.
struct FieldDefinitionDraft: Identifiable {
    let id: UUID = UUID() // SwiftUI list identity only
    var existingDefinition: FieldDefinition? // nil = new field being added
    var name: String
    var fieldType: FieldType
    var priority: Int
    /// How this field is surfaced in the item list. Normalised against the field type
    /// by `FieldDefinitionValidation` before save.
    var displayRole: DisplayRole = .none
    var numberOptions: NumberOptions = NumberOptions()
    var optionListOptions: OptionListOptions = OptionListOptions()
    var booleanOptions: BooleanOptions = BooleanOptions()
    /// Maps original option name → current renamed name, for cascading to FieldValue records on save.
    /// Handles chains: renaming A→B then B→C records as A→C.
    var pendingOptionRenames: [String: String] = [:]
    /// Option names that were deleted, for cascading to FieldValue records on save.
    var pendingOptionDeletions: Set<String> = []

    /// Whether two drafts describe the same field. `id` is SwiftUI identity only and differs
    /// between any two instances, so this is what "unchanged since loading" means. `priority`
    /// is left out too: the catalogue editor renumbers it on every drag, and the save derives
    /// it from array position, so position (see the array overload) is what matters.
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

/// Lightweight form state for a single field input during item editing.
struct FieldValueDraft: Identifiable {
    let id: UUID = UUID()
    let fieldDefinition: FieldDefinition
    /// Captured at creation so the draft stays usable if its definition is deleted (on
    /// another device, while the sheet is open) — a deleted model's properties are not
    /// safe to read.
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

    /// Whether the two drafts hold the same value for their type. Only the slot the type
    /// uses is compared, so a stray value left in another slot never reads as an edit.
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

/// What the edit sheet loaded, so the save can tell a field the user changed from one they
/// merely saw. A draft equal to its baseline is not written back: the stored value may have
/// moved on another device while the sheet was open, and writing the sheet's copy over it
/// would undo that edit. See `ItemSaveService`.
struct EditBaseline {
    var fieldDrafts: [FieldValueDraft]
    var photoDrafts: [PhotoDraft]
    var notes: String
}

// MARK: - Photo Draft

/// Lightweight form state for a photo during item editing.
struct PhotoDraft: Identifiable, Equatable {
    let id: UUID = UUID()
    var imageData: Data
    var caption: String = ""
    var priority: Int
    /// The stored `ItemPhoto` this draft was loaded from, so saving updates that record
    /// rather than deleting and re-uploading it. `nil` for a newly picked photo — and for a
    /// duplicated item's photos, which must become new records on the new item.
    var existingPhotoID: PersistentIdentifier? = nil
}
