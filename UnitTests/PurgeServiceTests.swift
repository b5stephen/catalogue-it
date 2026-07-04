//
//  PurgeServiceTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Purge Service Tests

/// Tests hard-deletion of soft-deleted items past the retention window.
@MainActor
struct PurgeServiceTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
    }

    @discardableResult
    private func makeItem(in catalogue: Catalogue, ctx: ModelContext, deletedDaysAgo: Int? = nil) -> CatalogueItem {
        let item = CatalogueItem(isWishlist: false)
        item.catalogue = catalogue
        if let deletedDaysAgo {
            item.deletedDate = daysAgo(deletedDaysAgo)
        }
        ctx.insert(item)
        return item
    }

    // MARK: - Tests

    @Test("Items soft-deleted longer ago than the retention period are hard-deleted")
    func expiredItemsArePurged() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Test")
        ctx.insert(catalogue)
        makeItem(in: catalogue, ctx: ctx, deletedDaysAgo: PurgeService.retentionDays + 5)
        try ctx.save()

        PurgeService.purgeExpiredItems(for: catalogue, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<CatalogueItem>()).isEmpty)
    }

    @Test("Recently soft-deleted and active items survive a purge")
    func recentAndActiveItemsSurvive() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Test")
        ctx.insert(catalogue)
        let active = makeItem(in: catalogue, ctx: ctx)
        let recentlyDeleted = makeItem(in: catalogue, ctx: ctx, deletedDaysAgo: PurgeService.retentionDays - 5)
        let expired = makeItem(in: catalogue, ctx: ctx, deletedDaysAgo: PurgeService.retentionDays + 5)
        try ctx.save()

        PurgeService.purgeExpiredItems(for: catalogue, in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CatalogueItem>())
        #expect(remaining.count == 2)
        #expect(remaining.contains(active))
        #expect(remaining.contains(recentlyDeleted))
        #expect(remaining.contains(expired) == false)
    }

    @Test("Purging one catalogue does not touch expired items in another")
    func purgeIsScopedToCatalogue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let target = Catalogue(name: "Target")
        ctx.insert(target)
        let other = Catalogue(name: "Other")
        ctx.insert(other)
        makeItem(in: target, ctx: ctx, deletedDaysAgo: PurgeService.retentionDays + 5)
        let otherExpired = makeItem(in: other, ctx: ctx, deletedDaysAgo: PurgeService.retentionDays + 5)
        try ctx.save()

        PurgeService.purgeExpiredItems(for: target, in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CatalogueItem>())
        #expect(remaining == [otherExpired])
    }

    @Test("Purging removes the expired item's field values and photos")
    func purgeRemovesChildren() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Test")
        ctx.insert(catalogue)
        let fieldDef = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        fieldDef.catalogue = catalogue
        ctx.insert(fieldDef)

        let expired = makeItem(in: catalogue, ctx: ctx, deletedDaysAgo: PurgeService.retentionDays + 5)
        let fv = FieldValue(fieldDefinition: fieldDef, fieldType: .text)
        fv.textValue = "Spitfire"
        fv.item = expired
        ctx.insert(fv)
        let photo = ItemPhoto(imageData: Data([0xFF, 0xD8, 0xFF]), priority: 0)
        photo.item = expired
        ctx.insert(photo)
        try ctx.save()

        PurgeService.purgeExpiredItems(for: catalogue, in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<FieldValue>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ItemPhoto>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FieldDefinition>()).count == 1, "Definitions are not item children")
    }
}
