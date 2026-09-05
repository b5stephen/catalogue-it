//
//  CatalogueOptionsTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import catalogue_it

// MARK: - Catalogue Options Tests

/// Covers deriving the tab bar and flag filters from a catalogue's field definitions —
/// the projection the item list UI and the filter predicates both read.
@MainActor
struct CatalogueOptionsTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeCatalogue(in ctx: ModelContext) -> Catalogue {
        let catalogue = Catalogue(name: "Films")
        ctx.insert(catalogue)
        return catalogue
    }

    @discardableResult
    private func addOptionListStatus(
        to catalogue: Catalogue,
        in ctx: ModelContext,
        options: [String],
        defaultValue: String? = nil,
        priority: Int = 0
    ) -> FieldDefinition {
        let field = FieldDefinition(name: "Status", fieldType: .optionList, priority: priority, displayRole: .statusTabs)
        field.fieldOptions = .optionList(OptionListOptions(options: options, defaultValue: defaultValue))
        field.catalogue = catalogue
        ctx.insert(field)
        return field
    }

    // MARK: - No Status Field

    @Test("A catalogue with no status field offers no tabs")
    func noStatusFieldMeansNoTabs() throws {
        let container = try makeContainer()
        let catalogue = makeCatalogue(in: container.mainContext)
        #expect(catalogue.statusField == nil)
        // The UI hides the picker entirely on an empty list rather than showing one tab.
        #expect(catalogue.statusTabDescriptors.isEmpty)
        #expect(catalogue.defaultStatusTab == .all)
    }

    // MARK: - Option List Backed

    @Test("Tabs follow the field's defined option order, not alphabetical order")
    func tabsUseDefinedOrder() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)
        addOptionListStatus(to: catalogue, in: ctx, options: ["Owned", "Ordered", "Wishlist"])

        #expect(catalogue.statusTabDescriptors.map(\.label) == ["Owned", "Ordered", "Wishlist"])
    }

    @Test("The All tab is off by default")
    func allTabIsOffByDefault() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)
        addOptionListStatus(to: catalogue, in: ctx, options: ["Owned", "Wishlist"])

        #expect(catalogue.showAllTab == false)
        #expect(!catalogue.statusTabDescriptors.contains { $0.tab == .all })
    }

    @Test("The All tab can be turned on, and leads the tab order")
    func allTabIsOptional() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)
        catalogue.showAllTab = true
        addOptionListStatus(to: catalogue, in: ctx, options: ["Owned", "Wishlist"])

        #expect(catalogue.statusTabDescriptors.map(\.label) == ["All", "Owned", "Wishlist"])
    }

    @Test("New items default to the configured default option")
    func newItemsUseConfiguredDefault() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)
        addOptionListStatus(to: catalogue, in: ctx, options: ["Owned", "Wishlist"], defaultValue: "Wishlist")

        #expect(catalogue.defaultStatusTabForNewItems == .option("Wishlist"))
    }

    @Test("New items fall back to the first option when no default is set")
    func newItemsFallBackToFirstOption() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)
        addOptionListStatus(to: catalogue, in: ctx, options: ["Owned", "Wishlist"])

        #expect(catalogue.defaultStatusTabForNewItems == .option("Owned"))
    }

    // MARK: - Boolean Backed

    @Test("A boolean status produces two tabs using its configured labels")
    func booleanStatusUsesLabels() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)

        let field = FieldDefinition(name: "Wishlist", fieldType: .boolean, priority: 0, displayRole: .statusTabs)
        field.fieldOptions = .boolean(BooleanOptions(trueLabel: "Wanted", falseLabel: "Have"))
        field.catalogue = catalogue
        ctx.insert(field)

        #expect(catalogue.statusTabDescriptors.map(\.label) == ["Wanted", "Have"])
    }

    @Test("An unlabelled boolean status falls back to Yes and No")
    func booleanStatusLabelFallbacks() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)

        let field = FieldDefinition(name: "Wishlist", fieldType: .boolean, priority: 0, displayRole: .statusTabs)
        field.catalogue = catalogue
        ctx.insert(field)

        #expect(field.statusTabLabels.trueLabel == "Yes")
        #expect(field.statusTabLabels.falseLabel == "No")
    }

    @Test("Blank labels are treated as unset")
    func blankLabelsFallBack() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)

        let field = FieldDefinition(name: "Wishlist", fieldType: .boolean, priority: 0, displayRole: .statusTabs)
        field.fieldOptions = .boolean(BooleanOptions(trueLabel: "   ", falseLabel: ""))
        field.catalogue = catalogue
        ctx.insert(field)

        #expect(field.statusTabLabels.trueLabel == "Yes")
        #expect(field.statusTabLabels.falseLabel == "No")
    }

    // MARK: - Flags

    @Test("Flag fields are listed in field order and exclude plain booleans")
    func flagFieldsAreOrderedAndFiltered() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)

        for (index, name) in ["For Sale", "Favourite"].enumerated() {
            let flag = FieldDefinition(name: name, fieldType: .boolean, priority: index, displayRole: .flagFilter)
            flag.catalogue = catalogue
            ctx.insert(flag)
        }
        let plain = FieldDefinition(name: "Watched", fieldType: .boolean, priority: 2)
        plain.catalogue = catalogue
        ctx.insert(plain)

        #expect(catalogue.flagFields.map(\.name) == ["For Sale", "Favourite"])
    }

    // MARK: - Flag Appearance

    @Test("A flag with no configured appearance has no icon or colour")
    func flagAppearanceDefaults() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)

        let flag = FieldDefinition(name: "Favourite", fieldType: .boolean, priority: 0, displayRole: .flagFilter)
        flag.catalogue = catalogue
        ctx.insert(flag)

        // Appearance is optional in the real sense: rows and cards draw no badge at all
        // rather than falling back to a shared symbol that makes every flag look alike.
        #expect(flag.flagIconName == nil)
        #expect(flag.flagColor == nil)
    }

    @Test("A configured icon and colour are used")
    func flagAppearanceOverrides() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)

        let flag = FieldDefinition(name: "For Sale", fieldType: .boolean, priority: 0, displayRole: .flagFilter)
        flag.fieldOptions = .boolean(BooleanOptions(flagIconName: "tag.fill", flagColorHex: "#FF0000"))
        flag.catalogue = catalogue
        ctx.insert(flag)

        #expect(flag.flagIconName == "tag.fill")
        #expect(flag.flagColor == Color(hex: "#FF0000"))
    }

    @Test("A blank icon name reads as no icon rather than rendering a blank symbol")
    func blankFlagIconIsNoIcon() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)

        let flag = FieldDefinition(name: "Favourite", fieldType: .boolean, priority: 0, displayRole: .flagFilter)
        // An empty symbol name renders as a blank space, so it must never reach the badge.
        flag.fieldOptions = .boolean(BooleanOptions(flagIconName: "   ", flagColorHex: " "))
        flag.catalogue = catalogue
        ctx.insert(flag)

        #expect(flag.flagIconName == nil)
        #expect(flag.flagColor == nil)
    }

    @Test("An icon with no colour keeps the icon")
    func iconWithoutColour() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)

        let flag = FieldDefinition(name: "Favourite", fieldType: .boolean, priority: 0, displayRole: .flagFilter)
        flag.fieldOptions = .boolean(BooleanOptions(flagIconName: "star.fill"))
        flag.catalogue = catalogue
        ctx.insert(flag)

        // The two are independent — clearing the colour must not clear the badge.
        #expect(flag.flagIconName == "star.fill")
        #expect(flag.flagColor == nil)
    }

    @Test("Several flags keep independent appearances")
    func flagsHaveIndependentAppearance() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)

        let favourite = FieldDefinition(name: "Favourite", fieldType: .boolean, priority: 0, displayRole: .flagFilter)
        favourite.fieldOptions = .boolean(BooleanOptions(flagIconName: "star.fill", flagColorHex: "#FFCC00"))
        favourite.catalogue = catalogue
        ctx.insert(favourite)

        let repair = FieldDefinition(name: "Needs Repair", fieldType: .boolean, priority: 1, displayRole: .flagFilter)
        repair.fieldOptions = .boolean(BooleanOptions(flagIconName: "wrench.fill", flagColorHex: "#FF3B30"))
        repair.catalogue = catalogue
        ctx.insert(repair)

        // The point of per-flag appearance: a row carrying both is readable at a glance.
        #expect(catalogue.flagFields.map(\.flagIconName) == ["star.fill", "wrench.fill"])
        #expect(favourite.flagColor != repair.flagColor)
    }

    @Test("Appearance settings survive a Codable round-trip through FieldOptions")
    func flagAppearanceRoundTrips() throws {
        let options = BooleanOptions(
            trueLabel: "Wanted",
            falseLabel: "Have",
            defaultValue: true,
            flagIconName: "bookmark.fill",
            flagColorHex: "#00FF00"
        )
        let encoded = try JSONEncoder().encode(FieldOptions.boolean(options))
        let decoded = try JSONDecoder().decode(FieldOptions.self, from: encoded)
        #expect(decoded == .boolean(options))
    }

    @Test("Options written without appearance keys still decode")
    func booleanOptionsWithoutAppearanceDecode() throws {
        // Absent keys must decode as "no appearance configured", not fail.
        let json = #"{"boolean":{"_0":{"defaultValue":true,"trueLabel":"Wanted"}}}"#
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(FieldOptions.self, from: data)

        guard case .boolean(let options) = decoded else {
            Issue.record("Expected a boolean options blob")
            return
        }
        #expect(options.trueLabel == "Wanted")
        #expect(options.defaultValue == true)
        #expect(options.flagIconName == nil)
        #expect(options.flagColorHex == nil)
    }

    // MARK: - Selection Reconciliation

    @Test("A selection that no longer exists is clamped to the first tab")
    func staleSelectionIsClamped() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)
        addOptionListStatus(to: catalogue, in: ctx, options: ["Owned", "Wishlist"])

        // "Ordered" was removed on another device; the view must not keep filtering on it.
        #expect(catalogue.resolvedStatusTab(.option("Ordered")) == .option("Owned"))
    }

    @Test("A still-valid selection is left alone")
    func validSelectionIsPreserved() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)
        catalogue.showAllTab = true
        addOptionListStatus(to: catalogue, in: ctx, options: ["Owned", "Wishlist"])

        #expect(catalogue.resolvedStatusTab(.option("Wishlist")) == .option("Wishlist"))
        #expect(catalogue.resolvedStatusTab(.all) == .all)
    }

    @Test("Any selection collapses to All once the status field is gone")
    func selectionCollapsesWithoutStatusField() throws {
        let container = try makeContainer()
        let catalogue = makeCatalogue(in: container.mainContext)
        #expect(catalogue.resolvedStatusTab(.option("Owned")) == .all)
    }

    @Test("Two status fields resolve deterministically to the lowest priority")
    func duplicateStatusFieldsResolveDeterministically() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let catalogue = makeCatalogue(in: ctx)
        // Validation prevents this locally, but two devices can each add one before a merge.
        addOptionListStatus(to: catalogue, in: ctx, options: ["Owned", "Wishlist"], priority: 1)
        let first = addOptionListStatus(to: catalogue, in: ctx, options: ["New", "Used"], priority: 0)

        #expect(catalogue.statusField?.fieldID == first.fieldID)
    }
}
