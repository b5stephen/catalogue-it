//
//  ExportScopeTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Export Scope Tests

@MainActor
struct ExportScopeTests {

    private func fingerprint(search: String = "", tab: StatusTab = .all, flags: [UUID] = []) throws -> FilterFingerprint {
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let catalogue = Catalogue(name: "Planes")
        container.mainContext.insert(catalogue)
        return FilterFingerprint(catalogue: catalogue, statusTab: tab, activeFlagIDs: flags, searchText: search)
    }

    @Test("A list showing everything has no scope to choose")
    func unfilteredHasNoFilters() throws {
        #expect(ExportFilters(fingerprint: try fingerprint(), allCount: 10) == nil)
    }

    @Test("A search or a flag filter offers the scope")
    func filteredOffersScope() throws {
        #expect(ExportFilters(fingerprint: try fingerprint(search: "spit"), allCount: 10) != nil)
        #expect(ExportFilters(fingerprint: try fingerprint(flags: [UUID()]), allCount: 10) != nil)
    }

    @Test("Filtered keeps the list's filters, All drops them and keeps the sort")
    func selectionPerScope() throws {
        let current = try fingerprint(search: "spit")
        let filters = try #require(ExportFilters(fingerprint: current, allCount: 10))
        #expect(filters.selection(for: .filtered) == .matching(current, excluding: []))
        #expect(filters.selection(for: .all) == .matching(current.unfiltered, excluding: []))
        #expect(current.unfiltered.sortFieldKey == current.sortFieldKey)
    }

    @Test("Formats follow the item count")
    func availableFormats() {
        #expect(ExportFormat.available(forItemCount: 1) == [.message, .card, .spreadsheet])
        #expect(ExportFormat.available(forItemCount: 2) == [.message, .spreadsheet])
        #expect(ExportFormat.available(forItemCount: ExportFormat.messageItemLimit) == [.message, .spreadsheet])
        #expect(ExportFormat.available(forItemCount: ExportFormat.messageItemLimit + 1) == [.spreadsheet])
    }

    @Test("A selection opens on Message up to 20 items, then Spreadsheet")
    func defaultFormat() {
        #expect(ExportFormat.defaultFormat(forItemCount: 20) == .message)
        #expect(ExportFormat.defaultFormat(forItemCount: 21) == .spreadsheet)
    }
}
