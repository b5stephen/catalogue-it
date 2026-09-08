//
//  ItemFacetBuilderTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Item Facet Builder Tests

/// Covers the denormalised `statusValue` / `flagKeys` columns that the item list filters on.
/// These are a mirror of `FieldValue` data, so the risk they carry is drift: a mirror that
/// disagrees with the field values silently files items into the wrong tab.
@MainActor
struct ItemFacetBuilderTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    /// Builds a catalogue with an option-list status field, a flag field, and a plain field.
    private func makeCatalogue(in ctx: ModelContext) -> (Catalogue, status: FieldDefinition, flag: FieldDefinition, plain: FieldDefinition) {
        let catalogue = Catalogue(name: "Films")
        ctx.insert(catalogue)

        let plain = FieldDefinition(name: "Title", fieldType: .text, priority: 0)
        plain.catalogue = catalogue
        ctx.insert(plain)

        let status = FieldDefinition(name: "Status", fieldType: .optionList, priority: 1, displayRole: .statusTabs)
        status.fieldOptions = .optionList(OptionListOptions(options: ["Owned", "Wishlist"], defaultValue: "Owned"))
        status.catalogue = catalogue
        ctx.insert(status)

        let flag = FieldDefinition(name: "Favourite", fieldType: .boolean, priority: 2, displayRole: .flagFilter)
        flag.catalogue = catalogue
        ctx.insert(flag)

        return (catalogue, status, flag, plain)
    }

    @discardableResult
    private func addValue(
        _ def: FieldDefinition,
        to item: CatalogueItem,
        in ctx: ModelContext,
        text: String? = nil,
        bool: Bool? = nil
    ) -> FieldValue {
        let fv = FieldValue(fieldDefinition: def, fieldType: def.fieldType)
        fv.textValue = text
        fv.boolValue = bool
        fv.item = item
        ctx.insert(fv)
        return fv
    }

    // MARK: - Status

    @Test("An option-list status stores the option value verbatim")
    func optionListStatus() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, status, _, _) = makeCatalogue(in: ctx)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        addValue(status, to: item, in: ctx, text: "Wishlist")

        ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)
        #expect(item.statusValue == "Wishlist")
    }

    @Test("A status value no longer in the option set reads as unset")
    func staleOptionIsTreatedAsUnset() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, status, _, _) = makeCatalogue(in: ctx)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        // "Ordered" was removed from the field's options — no tab exists for it, so filing
        // the item under it would strand the item in a tab the user can't select.
        addValue(status, to: item, in: ctx, text: "Ordered")

        ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)
        #expect(item.statusValue == "")
    }

    @Test("A boolean status with no stored value falls to the false side")
    func booleanStatusDefaultsToFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Films")
        ctx.insert(catalogue)
        let status = FieldDefinition(name: "Wishlist", fieldType: .boolean, priority: 0, displayRole: .statusTabs)
        status.catalogue = catalogue
        ctx.insert(status)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        addValue(status, to: item, in: ctx, bool: nil)

        ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)
        // A boolean status is exhaustive: the item must land in one of the two tabs.
        #expect(item.statusValue == ItemFacetBuilder.boolFalseToken)
    }

    @Test("An item with no value for the status field has no status")
    func missingStatusValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _, plain) = makeCatalogue(in: ctx)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        addValue(plain, to: item, in: ctx, text: "Rashomon")

        ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)
        #expect(item.statusValue == "")
    }

    @Test("A field carrying a role its type can't support contributes no status")
    func invalidStatusFieldIsIgnored() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Films")
        ctx.insert(catalogue)
        // Option list with only one option — below the 2-option minimum for a tab bar.
        let status = FieldDefinition(name: "Status", fieldType: .optionList, priority: 0, displayRole: .statusTabs)
        status.fieldOptions = .optionList(OptionListOptions(options: ["Owned"]))
        status.catalogue = catalogue
        ctx.insert(status)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        addValue(status, to: item, in: ctx, text: "Owned")

        ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)
        #expect(item.statusValue == "")
        #expect(catalogue.statusField == nil)
    }

    // MARK: - Flags

    @Test("A set flag contributes its delimited token")
    func setFlagProducesToken() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, flag, _) = makeCatalogue(in: ctx)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        addValue(flag, to: item, in: ctx, bool: true)

        ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)
        #expect(item.flagKeys == ItemFacetBuilder.flagToken(for: flag.fieldID))
    }

    @Test("An unset flag contributes nothing")
    func unsetFlagProducesNoToken() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, flag, _) = makeCatalogue(in: ctx)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        addValue(flag, to: item, in: ctx, bool: false)

        ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)
        #expect(item.flagKeys == "")
    }

    @Test("Multiple flags concatenate, and each is independently matchable")
    func multipleFlagsAreIndependentlyMatchable() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, flagA, _) = makeCatalogue(in: ctx)

        let flagB = FieldDefinition(name: "For Sale", fieldType: .boolean, priority: 3, displayRole: .flagFilter)
        flagB.catalogue = catalogue
        ctx.insert(flagB)
        let flagC = FieldDefinition(name: "Needs Repair", fieldType: .boolean, priority: 4, displayRole: .flagFilter)
        flagC.catalogue = catalogue
        ctx.insert(flagC)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        addValue(flagA, to: item, in: ctx, bool: true)
        addValue(flagB, to: item, in: ctx, bool: false)
        addValue(flagC, to: item, in: ctx, bool: true)

        ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)

        // This is exactly how the pagination predicate tests membership.
        #expect(item.flagKeys.contains(ItemFacetBuilder.flagToken(for: flagA.fieldID)))
        #expect(!item.flagKeys.contains(ItemFacetBuilder.flagToken(for: flagB.fieldID)))
        #expect(item.flagKeys.contains(ItemFacetBuilder.flagToken(for: flagC.fieldID)))
    }

    @Test("Flag tokens are delimited so no token is a prefix of another")
    func flagTokensCannotPartiallyMatch() {
        let idA = UUID()
        let token = ItemFacetBuilder.flagToken(for: idA)
        #expect(token.hasPrefix("|"))
        #expect(token.hasSuffix("|"))
        // A bare UUID substring must not match a token lookup — the delimiters are load-bearing.
        #expect(!idA.uuidString.contains(token))
    }

    @Test("A boolean field with no display role contributes to neither column")
    func plainBooleanIsNotAFlag() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (catalogue, _, _, _) = makeCatalogue(in: ctx)

        let plainBool = FieldDefinition(name: "Watched", fieldType: .boolean, priority: 5)
        plainBool.catalogue = catalogue
        ctx.insert(plainBool)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        addValue(plainBool, to: item, in: ctx, bool: true)

        ItemFacetBuilder.apply(to: item, fieldValues: item.fieldValues, definitions: catalogue.fieldDefinitions)
        #expect(item.flagKeys == "")
        #expect(item.statusValue == "")
    }
}
