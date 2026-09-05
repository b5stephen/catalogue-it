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

    // MARK: - Role Assignment

    @Test("Choosing a status field demotes the previous holder")
    func choosingStatusFieldDemotesPrevious() {
        let drafts = [
            draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"]),
            draft("Condition", .optionList, role: .none, options: ["New", "Used"]),
        ]
        // The user picks the second field in the Options section's status picker.
        let result = FieldDefinitionValidation.settingStatusField(to: drafts[1].id, in: drafts)

        #expect(result[0].displayRole == DisplayRole.none)
        #expect(result[1].displayRole == .statusTabs)
    }

    @Test("Choosing a status field leaves flag fields untouched")
    func choosingStatusFieldKeepsFlags() {
        let drafts = [
            draft("Favourite", .boolean, role: .flagFilter),
            draft("Wishlist", .boolean, role: .none),
        ]
        let result = FieldDefinitionValidation.settingStatusField(to: drafts[1].id, in: drafts)

        #expect(result[0].displayRole == .flagFilter)
        #expect(result[1].displayRole == .statusTabs)
    }

    @Test("Choosing the field that already holds the role changes nothing")
    func choosingStatusFieldIsIdempotent() {
        let drafts = [
            draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"]),
            draft("Favourite", .boolean, role: .flagFilter),
        ]
        let result = FieldDefinitionValidation.settingStatusField(to: drafts[0].id, in: drafts)
        #expect(result[0].displayRole == .statusTabs)
        #expect(result[1].displayRole == .flagFilter)
    }

    @Test("Selecting None clears the tab bar without touching flags")
    func clearingStatusField() {
        let drafts = [
            draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"]),
            draft("Favourite", .boolean, role: .flagFilter),
        ]
        let result = FieldDefinitionValidation.settingStatusField(to: nil, in: drafts)
        #expect(result[0].displayRole == DisplayRole.none)
        #expect(result[1].displayRole == .flagFilter)
    }

    @Test("Promoting a flag field to status gives up its toggle")
    func statusFieldGivesUpItsFlag() {
        let drafts = [draft("Favourite", .boolean, role: .flagFilter)]
        let result = FieldDefinitionValidation.settingStatusField(to: drafts[0].id, in: drafts)
        #expect(result[0].displayRole == .statusTabs)
    }

    @Test("An ineligible field cannot be made the status field")
    func ineligibleFieldCannotTakeStatus() {
        let drafts = [
            draft("Status", .boolean, role: .statusTabs),
            draft("Notes", .text),
            draft("Condition", .optionList, options: ["New"]),
        ]
        // Neither a text field nor a one-option list can produce tabs, so the picker never
        // offers them — and the setter refuses even if one is passed.
        #expect(FieldDefinitionValidation.settingStatusField(to: drafts[1].id, in: drafts)[1].displayRole == DisplayRole.none)
        #expect(FieldDefinitionValidation.settingStatusField(to: drafts[2].id, in: drafts)[2].displayRole == DisplayRole.none)
        // The previous holder is still demoted — the user asked for "not Status".
        #expect(FieldDefinitionValidation.settingStatusField(to: drafts[1].id, in: drafts)[0].displayRole == DisplayRole.none)
    }

    @Test("statusFieldID reports the current holder, ignoring invalid claimants")
    func statusFieldIDReportsHolder() {
        let valid = [
            draft("Favourite", .boolean, role: .flagFilter),
            draft("Status", .optionList, role: .statusTabs, options: ["Owned", "Wishlist"]),
        ]
        #expect(FieldDefinitionValidation.statusFieldID(in: valid) == valid[1].id)
        // A field whose type was changed out from under the role isn't the holder.
        #expect(FieldDefinitionValidation.statusFieldID(in: [draft("Broken", .text, role: .statusTabs)]) == nil)
        #expect(FieldDefinitionValidation.statusFieldID(in: []) == nil)
    }

    // MARK: - Eligibility

    @Test("Only fields that could produce tabs are offered as status fields")
    func statusEligibility() {
        let drafts = [
            draft("Name", .text),
            draft("Year", .number),
            draft("Owned", .boolean),
            draft("Condition", .optionList, options: ["New"]),
            draft("Status", .optionList, options: ["Owned", "Wishlist"]),
        ]
        #expect(FieldDefinitionValidation.statusEligibleDrafts(in: drafts).map(\.name) == ["Owned", "Status"])
    }

    @Test("Only Yes/No fields are offered as filter toggles")
    func flagEligibility() {
        let drafts = [
            draft("Name", .text),
            draft("Favourite", .boolean),
            draft("Status", .optionList, options: ["Owned", "Wishlist"]),
            draft("For Sale", .boolean),
        ]
        #expect(FieldDefinitionValidation.flagEligibleDrafts(in: drafts).map(\.name) == ["Favourite", "For Sale"])
    }

    // MARK: - Filter Toggles

    @Test("Filter toggles are set and cleared independently of each other")
    func flagsToggleIndependently() {
        var drafts = [
            draft("Favourite", .boolean),
            draft("For Sale", .boolean),
        ]
        drafts = FieldDefinitionValidation.settingFlagFilter(true, for: drafts[0].id, in: drafts)
        drafts = FieldDefinitionValidation.settingFlagFilter(true, for: drafts[1].id, in: drafts)
        #expect(drafts.allSatisfy { $0.displayRole == .flagFilter })

        drafts = FieldDefinitionValidation.settingFlagFilter(false, for: drafts[0].id, in: drafts)
        #expect(drafts[0].displayRole == DisplayRole.none)
        #expect(drafts[1].displayRole == .flagFilter)
    }

    @Test("The status field cannot also be a filter toggle")
    func statusFieldCannotBeFlagged() {
        let drafts = [draft("Owned", .boolean, role: .statusTabs)]
        let result = FieldDefinitionValidation.settingFlagFilter(true, for: drafts[0].id, in: drafts)
        #expect(result[0].displayRole == .statusTabs)
    }

    @Test("A non-boolean field cannot be a filter toggle")
    func nonBooleanCannotBeFlagged() {
        let drafts = [draft("Status", .optionList, options: ["Owned", "Wishlist"])]
        let result = FieldDefinitionValidation.settingFlagFilter(true, for: drafts[0].id, in: drafts)
        #expect(result[0].displayRole == DisplayRole.none)
    }
}
