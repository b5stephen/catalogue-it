//
//  SupportingTypeTests.swift
//  UnitTests
//

import Testing
import Foundation
@testable import catalogue_it

// MARK: - Item Sort Field Tests

struct ItemSortFieldTests {

    @Test("dateAdded round trips through its raw value")
    func dateAddedRoundTrip() {
        let raw = ItemSortField.dateAdded.rawValue
        #expect(raw == "__dateAdded")
        #expect(ItemSortField(rawValue: raw) == .dateAdded)
    }

    @Test("A field UUID round trips through its raw value")
    func fieldRoundTrip() {
        let id = UUID()
        let field = ItemSortField.field(id)
        #expect(field.rawValue == id.uuidString)
        #expect(ItemSortField(rawValue: field.rawValue) == .field(id))
    }

    @Test("Stale or invalid stored values fall back to dateAdded", arguments: [
        "", "not-a-uuid", "__somethingElse"
    ])
    func invalidRawValueFallsBack(raw: String) {
        #expect(ItemSortField(rawValue: raw) == .dateAdded)
    }
}

// MARK: - Item Layout Tests

@MainActor
struct ItemLayoutTests {

    @Test("next toggles between grid and list")
    func nextToggles() {
        #expect(ItemLayout.grid.next == .list)
        #expect(ItemLayout.list.next == .grid)
        #expect(ItemLayout.grid.next.next == .grid, "Toggling twice returns to the start")
    }

    @Test("The toggle icon and label describe the layout being switched to")
    func toggleDescribesNextLayout() {
        #expect(ItemLayout.list.nextLayoutIcon == "square.grid.2x2")
        #expect(ItemLayout.list.nextLayoutLabel == "View as Gallery")
        #expect(ItemLayout.grid.nextLayoutIcon == "list.bullet")
        #expect(ItemLayout.grid.nextLayoutLabel == "View as List")
    }
}

// MARK: - Persisted Raw Value Stability Tests

/// These raw values are persisted (SwiftData storage, export files, AppStorage).
/// Changing any of them silently breaks stored data, so they are pinned here.
@MainActor
struct PersistedRawValueTests {

    @Test("FieldType raw values are pinned to their on-disk representation")
    func fieldTypeRawValues() {
        #expect(FieldType.text.rawValue == "Text")
        #expect(FieldType.number.rawValue == "Number")
        #expect(FieldType.date.rawValue == "Date")
        #expect(FieldType.boolean.rawValue == "Yes/No")
        #expect(FieldType.optionList.rawValue == "Option List")
        #expect(FieldType.allCases.count == 5)
    }

    @Test("NumberFormat raw values are pinned")
    func numberFormatRawValues() {
        #expect(NumberFormat.number.rawValue == "Number")
        #expect(NumberFormat.currency.rawValue == "Currency")
    }

    @Test("ItemSortDirection raw values are pinned")
    func sortDirectionRawValues() {
        #expect(ItemSortDirection.ascending.rawValue == "asc")
        #expect(ItemSortDirection.descending.rawValue == "desc")
    }

    @Test("ItemLayout raw values are pinned")
    func itemLayoutRawValues() {
        #expect(ItemLayout.grid.rawValue == "grid")
        #expect(ItemLayout.list.rawValue == "list")
    }
}

// MARK: - Display Role Tests

@MainActor
struct DisplayRoleTests {

    @Test("Raw values are stable — they are the on-disk Codable keys")
    func rawValuesAreStable() {
        #expect(DisplayRole.none.rawValue == "none")
        #expect(DisplayRole.statusTabs.rawValue == "statusTabs")
        #expect(DisplayRole.flagFilter.rawValue == "flagFilter")
    }

    @Test("Status tabs accepts only exclusive field types")
    func statusTabsSupportedTypes() {
        #expect(DisplayRole.statusTabs.supportedFieldTypes == [.optionList, .boolean])
    }

    @Test("Flag filter accepts booleans only")
    func flagFilterSupportedTypes() {
        #expect(DisplayRole.flagFilter.supportedFieldTypes == [.boolean])
    }

    @Test("A flag filter displays exactly as no role", arguments: [nil, "star"])
    func flagFilterDisplaysAsNone(icon: String?) {
        for type in FieldType.allCases {
            #expect(DisplayRole.flagFilter.isSummaryField(fieldType: type, flagIconName: icon)
                == DisplayRole.none.isSummaryField(fieldType: type, flagIconName: icon))
            #expect(DisplayRole.flagFilter.showsIconBadge(fieldType: type, flagIconName: icon)
                == DisplayRole.none.showsIconBadge(fieldType: type, flagIconName: icon))
        }
    }

    @Test("An icon-less Yes/No field is a summary field; with an icon it is a badge")
    func booleanIconDecidesBadge() {
        #expect(DisplayRole.flagFilter.isSummaryField(fieldType: .boolean, flagIconName: nil))
        #expect(!DisplayRole.flagFilter.isSummaryField(fieldType: .boolean, flagIconName: "star"))
        #expect(DisplayRole.flagFilter.showsIconBadge(fieldType: .boolean, flagIconName: "star"))
    }

    @Test("A status field is neither a summary field nor a badge")
    func statusTabsHidesValue() {
        #expect(!DisplayRole.statusTabs.isSummaryField(fieldType: .boolean, flagIconName: "star"))
        #expect(!DisplayRole.statusTabs.showsIconBadge(fieldType: .boolean, flagIconName: "star"))
    }

    @Test("A blank icon name resolves to no icon")
    func blankIconResolvesToNil() {
        #expect(BooleanOptions(flagIconName: "  ").resolvedFlagIconName == nil)
        #expect(BooleanOptions(flagIconName: " star ").resolvedFlagIconName == "star")
    }
}

// MARK: - Status Tab Tests

@MainActor
struct StatusTabTests {

    @Test("The All tab applies no status filter")
    func allTabHasNoStoredValue() {
        #expect(StatusTab.all.storedValue == nil)
    }

    @Test("An option tab filters on the option value verbatim")
    func optionTabStoresItsValue() {
        #expect(StatusTab.option("Wishlist").storedValue == "Wishlist")
    }

    @Test("Boolean tabs use sentinels that cannot collide with a user-typed option")
    func booleanTabsUseSentinels() throws {
        let trueValue = try #require(StatusTab.boolTrue.storedValue)
        let falseValue = try #require(StatusTab.boolFalse.storedValue)
        #expect(trueValue == ItemFacetBuilder.boolTrueToken)
        #expect(falseValue == ItemFacetBuilder.boolFalseToken)
        #expect(trueValue != falseValue)
        // The \u{1} prefix is what makes collision with a real option impossible.
        #expect(trueValue.hasPrefix("\u{1}"))
        #expect(falseValue.hasPrefix("\u{1}"))
    }
}
