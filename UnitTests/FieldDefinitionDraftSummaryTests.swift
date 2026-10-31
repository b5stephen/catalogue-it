//
//  FieldDefinitionDraftSummaryTests.swift
//  UnitTests
//

import Testing
@testable import catalogue_it

// MARK: - Field Definition Draft Summary Tests

@MainActor
struct FieldDefinitionDraftSummaryTests {

    private func optionList(_ options: [String], default defaultValue: String? = nil) -> FieldDefinitionDraft {
        FieldDefinitionDraft(
            name: "Maker", fieldType: .optionList, priority: 0,
            optionListOptions: OptionListOptions(options: options, defaultValue: defaultValue)
        )
    }

    @Test("Option list variants drop names for +N, then end on the count alone")
    func optionListVariantsShorten() {
        let variants = optionList(["Revell", "Airfix", "Tamiya"], default: "Tamiya").summaryVariants
        #expect(variants == [
            "3 options · Tamiya (default), Airfix, Revell",
            "3 options · Tamiya (default), Airfix, +1",
            "3 options · Tamiya (default), +2",
            "3 options",
        ])
    }

    @Test("The longest variant is the full summary")
    func firstVariantIsSummary() {
        let field = optionList(["B", "A", "C", "D"])
        #expect(field.summaryVariants.first == field.summary)
    }

    @Test("Long lists cap the variants at eight names")
    func longListsCapped() {
        let variants = optionList((1...20).map { "Option \($0)" }).summaryVariants
        #expect(variants.count == 9)
        #expect(variants.first?.hasSuffix("+12") == true)
        #expect(variants.dropLast().last?.hasSuffix("+19") == true)
        #expect(variants.last == "20 options")
    }

    @Test("Short option lists and other types have a single variant")
    func singleVariant() {
        #expect(optionList([]).summaryVariants.count == 1)
        #expect(optionList(["Only"]).summaryVariants.count == 1)
        let text = FieldDefinitionDraft(name: "Notes", fieldType: .text, priority: 0)
        #expect(text.summaryVariants == [text.summary])
    }

    @Test("A Yes/No field with an icon shows the icon as its tile")
    func booleanIconIsTile() {
        var field = FieldDefinitionDraft(name: "Signed", fieldType: .boolean, priority: 0)
        #expect(field.tileSymbol == FieldType.boolean.icon)
        field.booleanOptions.flagIconName = "signature"
        #expect(field.tileSymbol == "signature")
        field.displayRole = .statusTabs
        #expect(field.tileSymbol == FieldType.boolean.icon)
    }
}
