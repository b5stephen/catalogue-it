//
//  CatalogueItemSort.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 25/03/2026.
//

import Foundation

// MARK: - Catalogue Item Sort

/// Stateless sort helpers extracted from CatalogueItemsView for testability.
enum CatalogueItemSort {

    /// Returns `items` sorted by `primaryField` (in `direction`), with ties broken by the
    /// subsequent fields in the catalogue's priority order (always ascending).
    static func sorted(
        _ items: [CatalogueItem],
        primaryField: ItemSortField,
        direction: ItemSortDirection,
        catalogue: Catalogue
    ) -> [CatalogueItem] {
        let asc = direction == .ascending
        let sortedFieldDefs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }

        // Fields used as tiebreakers: everything after the primary in priority order.
        let secondaryFields: [FieldDefinition]
        if case .field(let uuid) = primaryField,
           let idx = sortedFieldDefs.firstIndex(where: { $0.fieldID == uuid }) {
            secondaryFields = Array(sortedFieldDefs[(idx + 1)...])
        } else {
            // dateAdded primary: all fields are available as tiebreakers
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
            return false
        }
    }

    /// Compares two items on a single field.
    /// Returns `true` if `a` should come before `b` (ascending), `false` if after, or `nil` if equal.
    /// Items with no value for the field sort after items that have one.
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
            }
        }
    }
}
