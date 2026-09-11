//
//  FirstItemTests.swift
//  UITests
//

import XCTest

/// Creates a catalogue and adds its first item, checking the item is listed straight
/// away — the list starts on its empty state, and this is the one transition where a
/// store change has to replace that state rather than update an existing list.
@MainActor
final class FirstItemTests: XCTestCase {
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

    func testFirstItemInNewCatalogueAppearsImmediately() throws {
        // Create a catalogue with the default Name field.
        app.buttons["Add Catalogue"].tap()
        let nameField = app.textFields["catalogue-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Fresh")
        app.buttons["Create"].tap()

        // Open it: the empty state should be showing.
        let row = app.staticTexts["Fresh"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["No Items Yet"].waitForExistence(timeout: 3),
                      "A new catalogue should open on its empty state")

        // Add an item with only the Name field filled.
        app.buttons["Add Item"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("First item")
        app.buttons["Add"].tap()

        // The sheet closes and the list replaces the empty state without leaving the screen.
        XCTAssertTrue(app.staticTexts["1 item"].waitForExistence(timeout: 5),
                      "Item count should update")
        let item = app.staticTexts["First item"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "First item should be listed")
        XCTAssertTrue(item.isHittable, "First item should be on screen")
        XCTAssertFalse(app.buttons["Cancel"].exists, "Add sheet should have dismissed")
    }
}
