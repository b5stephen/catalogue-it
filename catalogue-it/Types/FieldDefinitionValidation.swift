//
//  FieldDefinitionValidation.swift
//  catalogue-it
//

import Foundation

// MARK: - Field Definition Validation

/// Written against plain `(fieldType, optionCount)` inputs so drafts and persisted
/// definitions share the same rules.
nonisolated enum FieldDefinitionValidation {

    static let minimumStatusOptions = 2

    // MARK: - Role Support

    static func supportsStatusTabs(fieldType: FieldType, optionCount: Int) -> Bool {
        switch fieldType {
        case .optionList: optionCount >= minimumStatusOptions
        case .boolean:    true
        case .text, .number, .date: false
        }
    }

    static func supportsStatusTabs(_ field: FieldDefinition) -> Bool {
        supportsStatusTabs(
            fieldType: field.fieldType,
            optionCount: field.optionListOptions?.options.count ?? 0
        )
    }

    static func supportsStatusTabs(_ draft: FieldDefinitionDraft) -> Bool {
        supportsStatusTabs(fieldType: draft.fieldType, optionCount: draft.optionListOptions.options.count)
    }

    static func supportsFlagFilter(fieldType: FieldType) -> Bool {
        fieldType == .boolean
    }

    static func supports(role: DisplayRole, fieldType: FieldType, optionCount: Int) -> Bool {
        switch role {
        case .none:       true
        case .statusTabs: supportsStatusTabs(fieldType: fieldType, optionCount: optionCount)
        case .flagFilter: supportsFlagFilter(fieldType: fieldType)
        }
    }

    // MARK: - Draft-Set Validation

    /// A type change resets an unsupported role rather than being blocked, which would trap
    /// the user on a mis-created field. Callers should warn first.
    static func resolvedRole(for draft: FieldDefinitionDraft) -> DisplayRole {
        supports(
            role: draft.displayRole,
            fieldType: draft.fieldType,
            optionCount: draft.optionListOptions.options.count
        ) ? draft.displayRole : .none
    }

    /// Status claims after the first in field order.
    static func excessStatusTabIndices(in drafts: [FieldDefinitionDraft]) -> [Int] {
        var seenStatus = false
        var excess: [Int] = []
        for (index, draft) in drafts.enumerated() where resolvedRole(for: draft) == .statusTabs {
            if seenStatus {
                excess.append(index)
            } else {
                seenStatus = true
            }
        }
        return excess
    }

    /// Applied on save, so no invalid combination reaches the store.
    static func normalised(_ drafts: [FieldDefinitionDraft]) -> [FieldDefinitionDraft] {
        var result = drafts
        for index in result.indices {
            result[index].displayRole = resolvedRole(for: result[index])
        }
        for index in excessStatusTabIndices(in: result) {
            result[index].displayRole = .none
        }
        return result
    }

    static func hasStatusField(in drafts: [FieldDefinitionDraft]) -> Bool {
        drafts.contains { resolvedRole(for: $0) == .statusTabs }
    }

    // MARK: - Role Assignment

    static func statusFieldID(in drafts: [FieldDefinitionDraft]) -> UUID? {
        drafts.first { resolvedRole(for: $0) == .statusTabs }?.id
    }

    static func statusEligibleDrafts(in drafts: [FieldDefinitionDraft]) -> [FieldDefinitionDraft] {
        drafts.filter { supportsStatusTabs($0) }
    }

    static func flagEligibleDrafts(in drafts: [FieldDefinitionDraft]) -> [FieldDefinitionDraft] {
        drafts.filter { supportsFlagFilter(fieldType: $0.fieldType) }
    }

    /// Enforces one-per-catalogue here, so the newest choice wins; `normalised` would keep
    /// the first in field order instead.
    static func settingStatusField(to id: UUID?, in drafts: [FieldDefinitionDraft]) -> [FieldDefinitionDraft] {
        var result = drafts
        for index in result.indices {
            if result[index].displayRole == .statusTabs { result[index].displayRole = .none }
            // A field can hold only one role, so taking the tab bar gives up any flag toggle.
            if result[index].id == id, supportsStatusTabs(result[index]) {
                result[index].displayRole = .statusTabs
            }
        }
        return result
    }

    /// Ignored for the status field: only the status picker gives that role up.
    static func settingFlagFilter(_ isOn: Bool, for id: UUID, in drafts: [FieldDefinitionDraft]) -> [FieldDefinitionDraft] {
        var result = drafts
        guard let index = result.firstIndex(where: { $0.id == id }),
              supportsFlagFilter(fieldType: result[index].fieldType),
              result[index].displayRole != .statusTabs
        else { return result }
        result[index].displayRole = isOn ? .flagFilter : .none
        return result
    }
}
