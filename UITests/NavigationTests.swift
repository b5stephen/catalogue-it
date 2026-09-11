//
//  NavigationTests.swift
//  UITests
//

import XCTest

/// Regression test for the back-button bug where `List(selection:)` in
/// `ItemListView` caused `NavigationSplitView` to push an extra detail column
/// on compact iPhone, corrupting the navigation stack so the back button jumped
/// all the way to the catalogue list instead of returning to the item list.
@MainActor
final class NavigationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        // Force list layout so the test always exercises the list code path.
        app.launchEnvironment["UITESTING_LAYOUT"] = "list"
        app.launch()
    }

    override func tearDown() async throws {
        app = nil
    }

    func testBackButtonReturnsToItemListNotCatalogueList() throws {
        // Tap the seeded catalogue. Use staticTexts rather than cells — SwiftUI
        // does not reliably propagate inner-view identifiers to the cell level.
        let catalogueText = app.staticTexts["Test Catalogue"]
        XCTAssertTrue(catalogueText.waitForExistence(timeout: 5),
                      "Catalogue should appear in the sidebar list")
        catalogueText.tap()

        // Verify we reached catalogue detail. The catalogue screen carries no bar title
        // until its band scrolls away, so the toolbar's Add Item button is the marker.
        let addItemButton = app.buttons["Add Item"]
        XCTAssertTrue(addItemButton.waitForExistence(timeout: 3),
                      "Should navigate to catalogue detail")

        // Tap the seeded item.
        let itemText = app.staticTexts["Test Item"]
        XCTAssertTrue(itemText.waitForExistence(timeout: 3),
                      "Item should appear in the list")
        itemText.tap()

        // Verify we reached item detail.
        let itemBar = app.navigationBars["Test Item"]
        XCTAssertTrue(itemBar.waitForExistence(timeout: 3),
                      "Should navigate to item detail")

        // Tap the back button. Scope it to the item's nav bar so a toolbar button
        // can't be hit by mistake; its label is "Back" because the catalogue screen
        // has no bar title for it to inherit.
        itemBar.buttons["BackButton"].tap()

        // Regression assertion: back should land on catalogue detail, not the
        // top-level catalogue list.
        XCTAssertTrue(addItemButton.waitForExistence(timeout: 3),
                      "Back button should return to catalogue detail")
        XCTAssertFalse(app.buttons["Add Catalogue"].exists,
                       "Should NOT have jumped all the way back to the catalogue list")
    }
}
