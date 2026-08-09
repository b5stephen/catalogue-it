//
//  FieldDefinitionValidation.swift
//  catalogue-it
//

import Foundation

// MARK: - Field Definition Validation

/// Rules governing which display roles a field may take.
///
/// The checks are written against lightweight `(fieldType, optionListOptions)` inputs
/// so both the persisted `FieldDefinition` and the in-flight `FieldDefinitionDraft`
/// can be validated by the same code — the field editor validates drafts before save,
/// and the model layer re-checks persisted state when deriving tabs.
nonisolated enum FieldDefinitionValidation {

    /// A `.singleSelect`-style field needs at least this many options to make a tab bar
    /// meaningful — one tab is not a choice.
    static let minimumStatusOptions = 2

    // MARK: - Role Support

    /// Whether a field of this shape can carry `.statusTabs`.
    /// Requires an exclusive type: `.optionList` with 2+ options, or `.boolean`.
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

    /// Whether a field of this shape can carry `.flagFilter`. Booleans only.
    static func supportsFlagFilter(fieldType: FieldType) -> Bool {
        fieldType == .boolean
    }

    /// Whether the given role is valid for a field of this shape.
    static func supports(role: DisplayRole, fieldType: FieldType, optionCount: Int) -> Bool {
        switch role {
        case .none:       true
        case .statusTabs: supportsStatusTabs(fieldType: fieldType, optionCount: optionCount)
        case .flagFilter: supportsFlagFilter(fieldType: fieldType)
        }
    }

    // MARK: - Draft-Set Validation

    /// The role a draft should end up with, given its current type and options.
    ///
    /// When a field's type is changed out from under its role, the role is **reset to
    /// `.none`** rather than the change being blocked — blocking would trap the user on a
    /// field they mis-created with no way back. Callers should warn before applying this.
    static func resolvedRole(for draft: FieldDefinitionDraft) -> DisplayRole {
        supports(
            role: draft.displayRole,
            fieldType: draft.fieldType,
            optionCount: draft.optionListOptions.options.count
        ) ? draft.displayRole : .none
    }

    /// Indices of drafts whose `.statusTabs` role must be dropped because an earlier
    /// draft already claims it. At most one status field is allowed per catalogue;
    /// the first one in priority order wins.
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

    /// Normalises a draft set so it satisfies every rule: roles unsupported by the
    /// current field type are reset, and any status role beyond the first is dropped.
    /// Applied on save so invalid combinations can never reach the store.
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

    /// Whether any draft currently claims a valid `.statusTabs` role.
    static func hasStatusField(in drafts: [FieldDefinitionDraft]) -> Bool {
        drafts.contains { resolvedRole(for: $0) == .statusTabs }
    }

    /// The name of the draft driving the tab bar, ignoring the one identified by `excluding`.
    ///
    /// Drives the warning shown when a second field is about to claim the role, so the user
    /// is told the tab bar is moving rather than discovering it after the fact.
    static func statusFieldName(in drafts: [FieldDefinitionDraft], excluding id: UUID?) -> String? {
        drafts.first { $0.id != id && resolvedRole(for: $0) == .statusTabs }?.name
    }

    /// Makes the draft identified by `id` the sole status field, demoting any other claimant.
    ///
    /// Called when a field is promoted to `.statusTabs` so the one-per-catalogue rule is
    /// enforced at the moment of the change. `normalised` would otherwise resolve the
    /// conflict by field order, which would silently discard the user's newest choice.
    static func assigningStatusRole(to id: UUID, in drafts: [FieldDefinitionDraft]) -> [FieldDefinitionDraft] {
        var result = drafts
        for index in result.indices where result[index].id != id && result[index].displayRole == .statusTabs {
            result[index].displayRole = .none
        }
        return result
    }
}
