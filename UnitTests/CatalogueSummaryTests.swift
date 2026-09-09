//
//  CatalogueSummaryTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Catalogue Summary Tests

/// Covers the counts behind the catalogue cards on the My Catalogues screen.
@MainActor
struct CatalogueSummaryTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    @discardableResult
    private func addItem(
        to catalogue: Catalogue,
        in ctx: ModelContext,
        status: String = "",
        deleted: Bool = false
    ) -> CatalogueItem {
        let item = CatalogueItem()
        item.catalogue = catalogue
        item.statusValue = status
        if deleted { item.deletedDate = .now }
        ctx.insert(item)
        return item
    }

    @discardableResult
    private func addStatusField(
        to catalogue: Catalogue,
        in ctx: ModelContext,
        options: [String]
    ) -> FieldDefinition {
        let field = FieldDefinition(name: "Status", fieldType: .optionList, priority: 0, displayRole: .statusTabs)
        field.fieldOptions = .optionList(OptionListOptions(options: options, defaultValue: nil))
        field.catalogue = catalogue
        ctx.insert(field)
        return field
    }

    // MARK: - Item Count

    @Test("Item count excludes soft-deleted items and other catalogues")
    func itemCountScope() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Planes")
        let other = Catalogue(name: "Stamps")
        ctx.insert(catalogue)
        ctx.insert(other)

        addItem(to: catalogue, in: ctx)
        addItem(to: catalogue, in: ctx)
        addItem(to: catalogue, in: ctx, deleted: true)
        addItem(to: other, in: ctx)

        #expect(CatalogueSummary.itemCount(for: catalogue, in: ctx) == 2)
        #expect(CatalogueSummary.itemCount(for: other, in: ctx) == 1)
    }

    // MARK: - Status Counts

    @Test("A catalogue with no status field reports no status counts")
    func noStatusFieldMeansNoCounts() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Planes")
        ctx.insert(catalogue)
        addItem(to: catalogue, in: ctx)

        #expect(CatalogueSummary.statusCounts(for: catalogue, in: ctx).isEmpty)
    }

    @Test("Status counts follow the catalogue's own tab order")
    func statusCountsUseTabOrder() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Planes")
        ctx.insert(catalogue)
        addStatusField(to: catalogue, in: ctx, options: ["Owned", "Wishlist"])

        addItem(to: catalogue, in: ctx, status: "Owned")
        addItem(to: catalogue, in: ctx, status: "Owned")
        addItem(to: catalogue, in: ctx, status: "Wishlist")
        // Soft-deleted items are excluded from the status breakdown too.
        addItem(to: catalogue, in: ctx, status: "Owned", deleted: true)

        let counts = CatalogueSummary.statusCounts(for: catalogue, in: ctx)
        #expect(counts.map(\.label) == ["Owned", "Wishlist"])
        #expect(counts.map(\.count) == [2, 1])
    }

    @Test("Empty statuses are dropped rather than shown as zero")
    func emptyStatusesDropped() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Planes")
        ctx.insert(catalogue)
        addStatusField(to: catalogue, in: ctx, options: ["Owned", "Wishlist", "Sold"])

        addItem(to: catalogue, in: ctx, status: "Wishlist")

        let counts = CatalogueSummary.statusCounts(for: catalogue, in: ctx)
        #expect(counts.map(\.label) == ["Wishlist"])
    }

    @Test("Populated statuses fill the chip slots, dropping empties first")
    func capAppliesAfterDroppingEmpties() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let catalogue = Catalogue(name: "Planes")
        ctx.insert(catalogue)
        addStatusField(to: catalogue, in: ctx, options: ["Owned", "Ordered", "Wishlist", "Sold"])

        // "Owned" is empty, so the three populated statuses take all three slots.
        addItem(to: catalogue, in: ctx, status: "Ordered")
        addItem(to: catalogue, in: ctx, status: "Wishlist")
        addItem(to: catalogue, in: ctx, status: "Sold")

        let counts = CatalogueSummary.statusCounts(for: catalogue, in: ctx, limit: 3)
        #expect(counts.map(\.label) == ["Ordered", "Wishlist", "Sold"])
    }
}
