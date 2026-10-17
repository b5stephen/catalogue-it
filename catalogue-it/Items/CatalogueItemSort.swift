//
//  CatalogueItemSort.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 25/03/2026.
//

import Foundation

// MARK: - Catalogue Item Sort

enum CatalogueItemSort {

    /// Ties break on the other fields in priority order (always ascending), then date added.
    static func sorted(
        _ items: [CatalogueItem],
        primaryField: ItemSortField,
        direction: ItemSortDirection,
        catalogue: Catalogue
    ) -> [CatalogueItem] {
        let asc = direction == .ascending
        let sortedFieldDefs = catalogue.sortedFieldDefinitions

        let secondaryFields: [FieldDefinition]
        if case .field(let uuid) = primaryField {
            secondaryFields = sortedFieldDefs.filter { $0.fieldID != uuid }
        } else {
            secondaryFields = sortedFieldDefs
        }

        return items.sorted { a, b in
            if let result = compare(a, b, byField: primaryField, fieldDefinitions: sortedFieldDefs) {
                return asc ? result : !result
            }
            for fieldDef in secondaryFields {
                if let result = compare(a, b, byField: .field(fieldDef.fieldID), fieldDefinitions: sortedFieldDefs) {
                    return result // tiebreakers always ascending
                }
            }
            if case .field = primaryField,
               let result = compare(a, b, byField: .dateAdded, fieldDefinitions: sortedFieldDefs) {
                return result
            }
            return false
        }
    }

    /// `nil` when equal. Items with no value sort after those with one.
    static func compare(
        _ a: CatalogueItem,
        _ b: CatalogueItem,
        byField field: ItemSortField,
        fieldDefinitions: [FieldDefinition]
    ) -> Bool? {
        switch field {
        case .dateAdded:
            if a.createdDate == b.createdDate { return nil }
            return a.createdDate < b.createdDate

        case .field(let fieldID):
            guard let def = fieldDefinitions.first(where: { $0.fieldID == fieldID }) else { return nil }
            let va = a.value(for: def)
            let vb = b.value(for: def)

            if va == nil && vb == nil { return nil }
            guard let va else { return false } // a missing → goes last
            guard let vb else { return true }  // b missing → b goes last

            switch va.fieldType {
            case .text:
                let ta = va.textValue ?? "", tb = vb.textValue ?? ""
                switch ta.localizedCompare(tb) {
                case .orderedAscending:  return true
                case .orderedDescending: return false
                case .orderedSame:       return nil
                }
            case .number:
                let na = va.numberValue ?? 0, nb = vb.numberValue ?? 0
                if na == nb { return nil }
                return na < nb
            case .date:
                let da = va.dateValue, db = vb.dateValue
                if da == db { return nil }
                guard let da else { return false }
                guard let db else { return true }
                return da < db
            case .boolean:
                let ba = va.boolValue ?? false, bb = vb.boolValue ?? false
                if ba == bb { return nil }
                return !ba // false < true
            case .optionList:
                let ta = va.textValue ?? "", tb = vb.textValue ?? ""
                switch ta.localizedCompare(tb) {
                case .orderedAscending:  return true
                case .orderedDescending: return false
                case .orderedSame:       return nil
                }
            }
        }
    }
}
