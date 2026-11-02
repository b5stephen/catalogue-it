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

    /// A flag filter only adds a toolbar filter, so it displays exactly as `.none`; only the tab
    /// bar's chips stand in for a field's value on items. Every display rule below goes through
    /// this, so saved fields, drafts and the editor's preview can't disagree.
    var displaysValueOnItems: Bool {
        switch self {
        case .none, .flagFilter: true
        case .statusTabs: false
        }
    }

    /// A Yes/No field with an icon is a badge on rows and cards rather than a summary line, and a
    /// tappable tile in the edit sheet. Pass `BooleanOptions.resolvedFlagIconName`.
    func showsIconBadge(fieldType: FieldType, flagIconName: String?) -> Bool {
        displaysValueOnItems && fieldType == .boolean && flagIconName != nil
    }

    /// Eligible for an item row's title and summary lines.
    func isSummaryField(fieldType: FieldType, flagIconName: String?) -> Bool {
        displaysValueOnItems && !showsIconBadge(fieldType: fieldType, flagIconName: flagIconName)
    }
}
