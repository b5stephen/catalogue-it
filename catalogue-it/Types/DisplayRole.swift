//
//  DisplayRole.swift
//  catalogue-it
//

import Foundation

// MARK: - Display Role

/// How a field is surfaced in the item list UI, beyond the detail-form editing
/// that every field already gets.
///
/// ⚠️ Do NOT change any raw value — these are the on-disk Codable keys.
nonisolated enum DisplayRole: String, Codable, CaseIterable {
    /// Ordinary field — detail form only. The default for every field.
    case none = "none"
    /// Drives the item-list tab bar. Requires an exclusive field type
    /// (`.optionList` with 2+ options, or `.boolean`). At most one per catalogue.
    case statusTabs = "statusTabs"
    /// Drives an independent toggle filter. Requires `.boolean`.
    /// Any number are allowed per catalogue.
    case flagFilter = "flagFilter"
}

extension DisplayRole {
    /// Field types this role can be applied to. `.optionList` additionally requires
    /// 2+ options — see `FieldDefinitionValidation`.
    var supportedFieldTypes: Set<FieldType> {
        switch self {
        case .none:       Set(FieldType.allCases)
        case .statusTabs: [.optionList, .boolean]
        case .flagFilter: [.boolean]
        }
    }
}
