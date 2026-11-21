//
//  ExportTests.swift
//  UITests
//

import XCTest

/// Drives the toolbar's Share… through to the share sheet, the one path
/// unit tests can't reach: the system asks for the data on its own queue.
@MainActor
final class ExportTests: XCTestCase {
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

    func testExportOpensTheComposerOnSpreadsheetAndShares() throws {
        openCatalogue()
        openToolbarEntry("Share…")

        let share = app.buttons["exportShareButton"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "The export composer should open")
        XCTAssertTrue(app.buttons["Spreadsheet"].isSelected, "The toolbar opens on Spreadsheet")
        XCTAssertFalse(app.segmentedControls["exportScopePicker"].exists, "Nothing is filtered")

        share.tap()
        assertShareSheet()
    }

    func testDataSharesAFile() throws {
        openCatalogue()
        openToolbarEntry("Share…")

        let share = app.buttons["exportShareButton"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "The export composer should open")
        app.buttons["Data"].tap()
        XCTAssertTrue(app.switches["Include photos"].exists, "Data offers to leave photos out")
        XCTAssertFalse(app.buttons["exportCopyButton"].exists, "Data has no Copy")

        share.tap()
        assertShareSheet()
    }

    // MARK: - Helpers

    private func assertShareSheet() {
        // The share sheet only renders once the data has been handed over; give the
        // export time to run, then check the app survived it.
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 10), "Share sheet should appear")
        XCTAssertEqual(app.state, .runningForeground, "App should not crash while exporting")
    }

    private func openCatalogue() {
        let catalogueText = app.staticTexts["Test Catalogue"].firstMatch
        XCTAssertTrue(catalogueText.waitForExistence(timeout: 5))
        catalogueText.tap()
        XCTAssertTrue(app.buttons["Add Item"].waitForExistence(timeout: 3))
    }

    private func openToolbarEntry(_ label: String) {
        // iOS folds secondary actions into the "…" overflow when the bar runs out of room.
        let entry = app.buttons[label].firstMatch
        if !entry.waitForExistence(timeout: 1) {
            app.buttons["More"].firstMatch.tap()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 3), "\(label) should be reachable")
        entry.tap()
    }
}
