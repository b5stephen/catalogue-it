//
//  FieldDisplayRoleValidationTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Validation Tests

/// Covers the rules that keep display roles coherent: which types can carry which role,
/// and the one-status-field-per-catalogue limit.
@MainActor
struct FieldDisplayRoleValidationTests {

    private func draft(
        _ name: String,
        _ type: FieldType,
        role: DisplayRole = .none,
        options: [String] = []
    ) -> FieldDefinitionDraft {
        var d = FieldDefinitionDraft(name: name, fieldType: type, priority: 0)
        d.displayRole = role
        d.optionListOptions = OptionListOptions(options: options)
        return d
    }

    // MARK: - Type Support

    @Test("Status tabs require an option list with at least two options")
    func statusTabsNeedTwoOptions() {
        #expect(!FieldDefinitionValidation.supportsStatusTabs(fieldType: .optionList, optionCount: 0))
        #expect(!FieldDefinitionValidation.supportsStatusTabs(fieldType: .optionList, optionCount: 1))
        #expect(FieldDefinitionValidation.supportsStatusTabs(fieldType: .optionList, optionCount: 2))
    }

    @Test("Booleans can always carry status tabs")
    func booleansSupportStatusTabs() {
        #expect(FieldDefinitionValidation.supportsStatusTabs(fieldType: .boolean, optionCount: 0))
    }

    @Test("Non-exclusive types can never carry status tabs")
    func nonExclusiveTypesRejected() {
        for type in [FieldType.text, .number, .date] {
            #expect(!FieldDefinitionValidation.supportsStatusTabs(fieldType: type, optionCount: 99))
        }
    }

    @Test("Flag filters require a boolean")
    func flagFiltersRequireBoolean() {
        #expect(FieldDefinitionValidation.supportsFlagFilter(fieldType: .boolean))
        for type in [FieldType.text, .number, .date, .optionList] {
            #expect(!FieldDefinitionValidation.supportsFlagFilter(fieldType: type))
        }
    }

    @Test("The default role is valid on every field type")
    func noneIsAlwaysValid() {
        for type in FieldType.allCases {
            #expect(FieldDefinitionValidation.supports(role: .none, fieldType: type, optionCount: 0))
        }
    }

    // MARK: - Type Changes

    @Test("Changing a field's type away from a supported one resets the role rather than blocking")
    func typeChangeResetsRole() {
        // A status field switched to Text: the role can't survive, but the edit is allowed.
        let changed = draft("Status", .text, role: .statusTabs, options: ["Owned", "Wishlist"])
        #expect(FieldDefinitionValidation.resolvedRole(for: changed) == DisplayRole.none)
    }

    @Test("Dropping below two options invalidates a status role")
    func removingOptionsResetsStatusRole() {
        let reduced = draft("Status", .optionList, role: .statusTabs, options: ["Owned"])
        #expect(FieldDefinitionValidation.resolvedRole(for: reduced) == DisplayRole.none)
    }

    @Test("A valid role survives normalisation untouched")
    func validRoleIsPreserved() {
        let valid = draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"])
        #expect(FieldDefinitionValidation.resolvedRole(for: valid) == .statusTabs)
    }

    // MARK: - One Status Field

    @Test("Only the first status field survives normalisation")
    func secondStatusFieldIsDemoted() {
        let drafts = [
            draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"]),
            draft("Condition", .optionList, role: .statusTabs, options: ["New", "Used"]),
        ]
        let normalised = FieldDefinitionValidation.normalised(drafts)
        #expect(normalised[0].displayRole == .statusTabs)
        // A second exclusive dimension becomes a plain field, per the one-tab-bar rule.
        #expect(normalised[1].displayRole == DisplayRole.none)
    }

    @Test("Any number of flag fields survive normalisation")
    func multipleFlagsAreAllowed() {
        let drafts = [
            draft("Favourite", .boolean, role: .flagFilter),
            draft("For Sale", .boolean, role: .flagFilter),
            draft("Needs Repair", .boolean, role: .flagFilter),
        ]
        let normalised = FieldDefinitionValidation.normalised(drafts)
        #expect(normalised.allSatisfy { $0.displayRole == .flagFilter })
    }

    @Test("An invalid first status field lets a valid later one take the role")
    func invalidStatusDoesNotConsumeTheSlot() {
        let drafts = [
            // Invalid: only one option, so it never counted as a status field.
            draft("Broken", .optionList, role: .statusTabs, options: ["Only"]),
            draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"]),
        ]
        let normalised = FieldDefinitionValidation.normalised(drafts)
        #expect(normalised[0].displayRole == DisplayRole.none)
        #expect(normalised[1].displayRole == .statusTabs)
    }

    @Test("hasStatusField ignores drafts whose role would be reset")
    func hasStatusFieldRespectsValidity() {
        #expect(!FieldDefinitionValidation.hasStatusField(in: [draft("Broken", .text, role: .statusTabs)]))
        #expect(FieldDefinitionValidation.hasStatusField(in: [draft("Wishlist", .boolean, role: .statusTabs)]))
    }

    // MARK: - Claiming the Status Role

    @Test("Promoting a field to status tabs demotes the previous holder")
    func claimingStatusRoleDemotesPrevious() {
        var drafts = [
            draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"]),
            draft("Condition", .optionList, role: .none, options: ["New", "Used"]),
        ]
        // The user promotes the second field via its Display options.
        drafts[1].displayRole = .statusTabs
        let result = FieldDefinitionValidation.assigningStatusRole(to: drafts[1].id, in: drafts)

        // Newest choice wins — the opposite of what field-order normalisation would do.
        #expect(result[0].displayRole == DisplayRole.none)
        #expect(result[1].displayRole == .statusTabs)
    }

    @Test("Claiming the status role leaves flag fields untouched")
    func claimingStatusRoleKeepsFlags() {
        var drafts = [
            draft("Favourite", .boolean, role: .flagFilter),
            draft("Wishlist", .boolean, role: .none),
        ]
        drafts[1].displayRole = .statusTabs
        let result = FieldDefinitionValidation.assigningStatusRole(to: drafts[1].id, in: drafts)

        #expect(result[0].displayRole == .flagFilter)
        #expect(result[1].displayRole == .statusTabs)
    }

    @Test("Claiming the role a field already holds changes nothing")
    func reclaimingIsIdempotent() {
        let drafts = [
            draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"]),
            draft("Favourite", .boolean, role: .flagFilter),
        ]
        let result = FieldDefinitionValidation.assigningStatusRole(to: drafts[0].id, in: drafts)
        #expect(result[0].displayRole == .statusTabs)
        #expect(result[1].displayRole == .flagFilter)
    }

    @Test("statusFieldName reports the other holder, and nothing when it is the field itself")
    func statusFieldNameExcludesSelf() {
        let drafts = [
            draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"]),
            draft("Favourite", .boolean, role: .flagFilter),
        ]
        // Asked on behalf of the Favourite field: the tab bar would be taken from "Status".
        #expect(FieldDefinitionValidation.statusFieldName(in: drafts, excluding: drafts[1].id) == "Status")
        // Asked on behalf of Status itself: it already holds the role, so there's no warning.
        #expect(FieldDefinitionValidation.statusFieldName(in: drafts, excluding: drafts[0].id) == nil)
        // Asked for a brand-new field: the existing holder is reported.
        #expect(FieldDefinitionValidation.statusFieldName(in: drafts, excluding: nil) == "Status")
    }

    @Test("An invalid status claimant is not reported as the current holder")
    func statusFieldNameIgnoresInvalidClaimants() {
        let drafts = [draft("Broken", .text, role: .statusTabs)]
        #expect(FieldDefinitionValidation.statusFieldName(in: drafts, excluding: nil) == nil)
    }
}
