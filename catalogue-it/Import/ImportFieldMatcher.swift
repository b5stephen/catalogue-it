//
//  ImportFieldMatcher.swift
//  catalogue-it
//

import Foundation

// MARK: - Import Field Matcher

/// Decides, for each field in an imported catalogue, which field of an existing catalogue its
/// values go into, or that it is added as a new field. Pure, so the destination sheet's preview
/// and `ItemImporter` reach the same answer.
nonisolated enum ImportFieldMatcher {

    struct ExistingField: Equatable, Sendable {
        let fieldID: UUID
        let name: String
        let fieldType: FieldType
    }

    enum Match: Equatable, Sendable {
        case existing(fieldID: UUID, name: String)
        /// The name is made unique among the catalogue's fields.
        case new(name: String)
    }

    struct Entry: Identifiable, Equatable, Sendable {
        let fileFieldID: UUID
        let name: String
        let fieldType: FieldType
        let match: Match

        var id: UUID { fileFieldID }
    }

    /// One entry per file field, in the file's field order. A field matches by `fieldID` (the
    /// file came from this catalogue), then by name ignoring case and accents; either way only
    /// a field of the same type, and each existing field takes at most one file field.
    /// - Parameter byName: Off when the user has already chosen each field, as the column
    ///   mapping does: a column they made a new field must not merge into one of the same name.
    static func match(_ fileFields: [FieldDefinitionDTO], to existing: [ExistingField], byName: Bool = true) -> [Entry] {
        let ordered = fileFields.sorted {
            $0.priority != $1.priority ? $0.priority < $1.priority : $0.fieldID.uuidString < $1.fieldID.uuidString
        }
        var claimed = Set<UUID>()
        var matches: [UUID: ExistingField] = [:]

        for field in ordered {
            if let byID = existing.first(where: { $0.fieldID == field.fieldID && $0.fieldType == field.fieldType }) {
                matches[field.fieldID] = byID
                claimed.insert(byID.fieldID)
            }
        }
        for field in ordered where byName && matches[field.fieldID] == nil {
            let key = normalised(field.name)
            if let byName = existing.first(where: {
                !claimed.contains($0.fieldID) && $0.fieldType == field.fieldType && normalised($0.name) == key
            }) {
                matches[field.fieldID] = byName
                claimed.insert(byName.fieldID)
            }
        }

        var takenNames = Set(existing.map { normalised($0.name) })
        return ordered.map { field in
            let match: Match
            if let found = matches[field.fieldID] {
                match = .existing(fieldID: found.fieldID, name: found.name)
            } else {
                let name = uniqueName(field.name, among: takenNames)
                takenNames.insert(normalised(name))
                match = .new(name: name)
            }
            return Entry(fileFieldID: field.fieldID, name: field.name, fieldType: field.fieldType, match: match)
        }
    }

    static func normalised(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// `"Year"`, or `"Year 2"`, `"Year 3"`… when taken. `taken` holds normalised names.
    static func uniqueName(_ name: String, among taken: Set<String>) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard taken.contains(normalised(base)) else { return base }
        var suffix = 2
        while taken.contains(normalised("\(base) \(suffix)")) { suffix += 1 }
        return "\(base) \(suffix)"
    }
}

nonisolated extension ImportFieldMatcher.ExistingField {
    init(_ definition: FieldDefinition) {
        self.init(fieldID: definition.fieldID, name: definition.name, fieldType: definition.fieldType)
    }
}
