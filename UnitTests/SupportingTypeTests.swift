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

// MARK: - Item Tab Tests

@MainActor
struct ItemTabTests {

    @Test("All three tabs exist in display order")
    func tabCases() {
        #expect(ItemTab.allCases == [.all, .owned, .wishlist])
    }

    @Test("Each tab has a distinct system image")
    func tabImagesAreDistinct() {
        let images = ItemTab.allCases.map(\.systemImage)
        #expect(Set(images).count == images.count)
    }
}
