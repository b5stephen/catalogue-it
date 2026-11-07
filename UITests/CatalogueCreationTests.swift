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

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    override func tearDown() async throws {
        app = nil
    }

    func testCreateCatalogueWithAllFieldTypes() throws {
        // The app sits at 0% CPU throughout, so this is a UIKit animation whose completion never
        // fires (it follows the swipe on the form sheet), not work a user would notice.
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad,
                      "On iPad, after the form sheet is swiped, the app never reports its animations complete, so every later step waits out XCTest's 2-minute idle timeout")

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
        nameField.typeText("All Fields\n")

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
        // On iPad the form is a short sheet with the button below the fold, where the lazy
        // Form hasn't created it yet.
        let addFieldButton = app.buttons["Add Field"]
        for _ in 0..<5 where !(addFieldButton.exists && addFieldButton.isHittable) {
            app.swipeUp()
        }
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

        // Text is the default selection; any other type is a row in the Type list.
        if type != "Text" {
            let typeRow = app.buttons["field-type-\(type)"]
            XCTAssertTrue(typeRow.waitForExistence(timeout: 3),
                          "'\(type)' type row should be visible")
            typeRow.tap()
        }

        // Confirm the field.
        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        XCTAssertTrue(addButton.isEnabled, "Add button should be enabled after entering a name")
        addButton.tap()

        // The form's bar stays on screen while this sheet slides away, and a tap on Add Field
        // during that animation is dropped, so wait for this sheet to be gone.
        XCTAssertTrue(app.navigationBars["Add Field"].waitForNonExistence(timeout: 3),
                      "Should return to New Catalogue form after adding the field")
    }
}
