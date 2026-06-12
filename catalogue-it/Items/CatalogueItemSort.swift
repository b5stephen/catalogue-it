//
//  CatalogueItemSort.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 25/03/2026.
//

import Foundation
import SwiftData

// MARK: - Catalogue Item Sort

/// Stateless sort helpers extracted from CatalogueItemsView for testability.
enum CatalogueItemSort {

    /// Returns `items` sorted by `primaryField` (in `direction`), with ties broken by all other
    /// custom fields in priority order (always ascending), then finally by dateAdded ascending.
    ///
    /// Uses a decorate-sort-undecorate pass: each item's FieldValues are resolved into a
    /// `[UUID: FieldValue]` map once before sorting, so value lookups inside each pairwise
    /// comparison are O(1) rather than O(F) linear scans.
    ///
    /// Complexity: O(N·F) decoration + O(N log N·F) worst-case sort, effectively O(N log N)
    /// because comparisons short-circuit on the first distinguishing field.
    static func sorted(
        _ items: [CatalogueItem],
        primaryField: ItemSortField,
        direction: ItemSortDirection,
        catalogue: Catalogue
    ) -> [CatalogueItem] {
        let asc = direction == .ascending
        let sortedFieldDefs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }

        // Fields used as tiebreakers: all fields in priority order, except the primary.
        let secondaryFields: [FieldDefinition]
        if case .field(let uuid) = primaryField {
            secondaryFields = sortedFieldDefs.filter { $0.fieldID != uuid }
        } else {
            // dateAdded primary: all fields are available as tiebreakers
            secondaryFields = sortedFieldDefs
        }

        // Decorate: build per-item fieldID → FieldValue maps in one O(N·F) pass.
        // This avoids repeating O(F) value(for:) scans inside every pairwise comparison.
        let valueMaps: [PersistentIdentifier: [UUID: FieldValue]] = Dictionary(
            uniqueKeysWithValues: items.map { item in
                let map = Dictionary(
                    item.fieldValues.compactMap { fv -> (UUID, FieldValue)? in
                        guard let def = fv.fieldDefinition else { return nil }
                        return (def.fieldID, fv)
                    },
                    uniquingKeysWith: { first, _ in first }
                )
                return (item.persistentModelID, map)
            }
        )

        // Sort using the precomputed maps for O(1) per-field value lookups.
        return items.sorted { a, b in
            let mapA = valueMaps[a.persistentModelID] ?? [:]
            let mapB = valueMaps[b.persistentModelID] ?? [:]

            if let result = compareMapped(a, b, byField: primaryField, mapA: mapA, mapB: mapB) {
                return asc ? result : !result
            }
            for fieldDef in secondaryFields {
                if let result = compareMapped(a, b, byField: .field(fieldDef.fieldID), mapA: mapA, mapB: mapB) {
                    return result // tiebreakers always ascending
                }
            }
            // Final tiebreaker: dateAdded (unless it's already the primary sort)
            if case .field = primaryField,
               let result = compareMapped(a, b, byField: .dateAdded, mapA: mapA, mapB: mapB) {
                return result
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

    // MARK: - Private

    /// Map-backed compare used by `sorted`. Looks up field values in O(1) from precomputed maps.
    /// Ordering semantics are identical to the public `compare` overload.
    private static func compareMapped(
        _ a: CatalogueItem,
        _ b: CatalogueItem,
        byField field: ItemSortField,
        mapA: [UUID: FieldValue],
        mapB: [UUID: FieldValue]
    ) -> Bool? {
        switch field {
        case .dateAdded:
            if a.createdDate == b.createdDate { return nil }
            return a.createdDate < b.createdDate

        case .field(let fieldID):
            let va = mapA[fieldID]
            let vb = mapB[fieldID]

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
