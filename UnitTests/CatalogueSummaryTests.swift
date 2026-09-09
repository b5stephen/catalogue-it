//
//  CatalogueSummaryTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Catalogue Summary Tests

/// Covers the item count behind the catalogue cards on the My Catalogues screen.
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
        deleted: Bool = false
    ) -> CatalogueItem {
        let item = CatalogueItem()
        item.catalogue = catalogue
        if deleted { item.deletedDate = .now }
        ctx.insert(item)
        return item
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
}
