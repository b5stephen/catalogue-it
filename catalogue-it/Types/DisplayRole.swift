//
//  DisplayRole.swift
//  catalogue-it
//

import Foundation

// MARK: - Display Role

/// ⚠️ Never change a raw value — they are stored.
nonisolated enum DisplayRole: String, Codable, CaseIterable {
    case none = "none"
    /// The item-list tab bar. At most one per catalogue.
    case statusTabs = "statusTabs"
    /// A toggle filter. Any number per catalogue.
    case flagFilter = "flagFilter"
}

extension DisplayRole {
    /// `.optionList` also needs 2+ options — see `FieldDefinitionValidation`.
    var supportedFieldTypes: Set<FieldType> {
        switch self {
        case .none:       Set(FieldType.allCases)
        case .statusTabs: [.optionList, .boolean]
        case .flagFilter: [.boolean]
        }
    }
}
