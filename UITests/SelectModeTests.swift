//
//  SelectModeTests.swift
//  UITests
//

import XCTest

/// Deleting the seeded catalogue's single item, in select mode and from its card menu, and
/// sharing a selection through the export composer.
@MainActor
final class SelectModeTests: XCTestCase {
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

    func testSelectAllAndDelete() throws {
        openCatalogue()
        enterSelectMode()

        app.buttons["selectAllButton"].tap()
        XCTAssertTrue(selectedCount("1").waitForExistence(timeout: 3))

        app.buttons["selectionDeleteButton"].tap()
        XCTAssertTrue(app.staticTexts["Delete 1 Item?"].waitForExistence(timeout: 3), "Delete should ask first")
        app.buttons.matching(identifier: "Delete").allElementsBoundByIndex.last?.tap()

        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "The item should leave the list")
        XCTAssertFalse(app.buttons["selectAllButton"].exists, "Select mode should end")
    }

    func testCardMenuDeleteAsksFirst() throws {
        openCatalogue()

        row.press(forDuration: 1)
        let menuDelete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(menuDelete.waitForExistence(timeout: 3))
        menuDelete.tap()

        XCTAssertTrue(app.staticTexts["Delete \"Test Item\"?"].waitForExistence(timeout: 3), "Delete should ask first")
        // On iPad the dialog is a popover without a Cancel button; tapping outside dismisses it.
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["Delete \"Test Item\"?"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(row.exists, "Cancel should keep the item")
    }

    func testSharingASelectionOpensTheComposer() throws {
        openCatalogue()
        enterSelectMode()

        let share = app.buttons["selectionShareButton"]
        XCTAssertFalse(share.isEnabled, "Nothing is selected yet")

        row.tap()
        XCTAssertTrue(selectedCount("1").waitForExistence(timeout: 3))
        XCTAssertTrue(share.isEnabled)
        share.tap()

        XCTAssertTrue(app.buttons["exportShareButton"].waitForExistence(timeout: 5), "The export composer should open")
    }

    // MARK: - Helpers

    /// The list's row, not the item's title, which the detail column also shows on iPad.
    private var row: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "item-Test Item").firstMatch
    }

    /// On iPad the count sits in the list header's combined label, so match on a substring.
    private func selectedCount(_ count: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\(count) Selected")).firstMatch
    }

    private func openCatalogue() {
        let catalogue = app.staticTexts["Test Catalogue"].firstMatch
        XCTAssertTrue(catalogue.waitForExistence(timeout: 5))
        catalogue.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    private func enterSelectMode() {
        // iOS folds secondary actions into the "…" overflow when the bar runs out of room.
        // In the overflow menu the entry is found by its label, not its identifier.
        let select = app.buttons["Select"]
        if !select.waitForExistence(timeout: 1) {
            app.buttons["More"].firstMatch.tap()
        }
        XCTAssertTrue(select.waitForExistence(timeout: 3), "Select should be reachable")
        select.tap()
        XCTAssertTrue(app.buttons["selectAllButton"].waitForExistence(timeout: 3))
    }
}
