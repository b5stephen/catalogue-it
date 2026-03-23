//
//  CatalogueCreationTests.swift
//  UITests
//

import XCTest

/// Tests the end-to-end flow of creating a new catalogue with one field of
/// every supported type (Text, Number, Date, Yes/No), confirming it is saved
/// and appears in the catalogue list.
@MainActor
final class CatalogueCreationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testCreateCatalogueWithAllFieldTypes() throws {
        // Open the new catalogue sheet.
        let addButton = app.buttons["Add Catalogue"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5),
                      "Add Catalogue button should be visible in the toolbar")
        addButton.tap()

        // Verify the sheet appeared.
        XCTAssertTrue(app.navigationBars["New Catalogue"].waitForExistence(timeout: 3),
                      "New Catalogue sheet should appear")

        // Enter a catalogue name. Uses a stable accessibility identifier because
        // the form also contains an inline field row whose current value is "Name",
        // which would otherwise cause multiple matches on app.textFields["Name"].
        let nameField = app.textFields["catalogue-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("All Fields")

        // The default "Name" (Text) field is pre-seeded — Text type is covered.
        // Add a Number field.
        try addField(name: "Count", type: "Number")

        // Add a Date field.
        try addField(name: "Published", type: "Date")

        // Add a Yes/No (Boolean) field.
        try addField(name: "Available", type: "Yes/No")

        // Tap Create to save the catalogue.
        let createButton = app.buttons["Create"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 3))
        XCTAssertTrue(createButton.isEnabled, "Create button should be enabled")
        createButton.tap()

        // Confirm the catalogue appears in the sidebar list.
        XCTAssertTrue(app.staticTexts["All Fields"].waitForExistence(timeout: 5),
                      "Newly created catalogue should appear in the catalogue list")
    }

    // MARK: - Helpers

    /// Opens the Add Field sheet, enters a name, selects the given type, and confirms.
    private func addField(name: String, type: String) throws {
        let addFieldButton = app.buttons["Add Field"]
        XCTAssertTrue(addFieldButton.waitForExistence(timeout: 3),
                      "Add Field button should be visible")
        addFieldButton.tap()

        XCTAssertTrue(app.navigationBars["Add Field"].waitForExistence(timeout: 3),
                      "Add Field sheet should appear")

        // Enter the field name. Uses a stable identifier because underlying
        // FieldDefinitionRow TextFields (also placeholder "Field Name") are in the
        // accessibility tree while this sheet is presented.
        let fieldNameField = app.textFields["add-field-name"]
        XCTAssertTrue(fieldNameField.waitForExistence(timeout: 3))
        fieldNameField.tap()
        fieldNameField.typeText(name)

        // Open the type picker and select the option.
        // Tap the cell containing the "Type" label (the static text itself is not
        // hittable — the interactive area is its parent cell).
        if type != "Text" {
            let typeCell = app.cells.containing(.staticText, identifier: "Type").firstMatch
            XCTAssertTrue(typeCell.waitForExistence(timeout: 3),
                          "Type picker cell should be visible")
            typeCell.tap()

            // Works for both navigation-link and menu picker styles.
            let typeOption = app.buttons[type].firstMatch
            XCTAssertTrue(typeOption.waitForExistence(timeout: 3),
                          "'\(type)' option should appear after tapping picker")
            typeOption.tap()

            // Navigation-style pickers auto-pop back on selection;
            // wait for the Add Field form to return.
            XCTAssertTrue(app.navigationBars["Add Field"].waitForExistence(timeout: 3),
                          "Should return to Add Field form after picking type")
        }

        // Confirm the field.
        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        XCTAssertTrue(addButton.isEnabled, "Add button should be enabled after entering a name")
        addButton.tap()

        // Wait for the sheet to dismiss before proceeding.
        XCTAssertTrue(app.navigationBars["New Catalogue"].waitForExistence(timeout: 3),
                      "Should return to New Catalogue form after adding the field")
    }
}
