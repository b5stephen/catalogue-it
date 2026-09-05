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

    // MARK: - Role Assignment

    /// The draft currently driving the tab bar, if any. Drives the Options section's
    /// status picker selection; `nil` selects "None".
    static func statusFieldID(in drafts: [FieldDefinitionDraft]) -> UUID? {
        drafts.first { resolvedRole(for: $0) == .statusTabs }?.id
    }

    /// Drafts whose type could drive the tab bar, in field order. A field is offered in the
    /// status picker only if choosing it would actually produce tabs.
    static func statusEligibleDrafts(in drafts: [FieldDefinitionDraft]) -> [FieldDefinitionDraft] {
        drafts.filter { supportsStatusTabs($0) }
    }

    /// Drafts that could drive a filter toggle, in field order.
    static func flagEligibleDrafts(in drafts: [FieldDefinitionDraft]) -> [FieldDefinitionDraft] {
        drafts.filter { supportsFlagFilter(fieldType: $0.fieldType) }
    }

    /// Makes the draft identified by `id` the sole status field, demoting any other claimant.
    /// Passing `nil` clears the tab bar entirely.
    ///
    /// The one-per-catalogue rule is enforced here, at the moment of the change, so the
    /// user's newest choice wins — `normalised` would instead resolve a conflict by field
    /// order and silently discard it.
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

    /// Turns the filter toggle on or off for one draft, leaving every other field alone.
    /// Ignored for a field whose type can't carry the role, or that currently drives the
    /// tab bar — the status picker is the only way to give that role up.
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
