//
//  ExportTests.swift
//  UITests
//

import XCTest

/// Drives each Export menu entry through to the share sheet, the one path unit tests can't
/// reach: SwiftUI's ShareLink hands the Transferable to the system, which asks for the data
/// on its own queue.
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

    func testExportCSV() throws {
        try export(choosing: "Export as CSV")
    }

    func testExportJSONWithPhotos() throws {
        try export(choosing: "Export as JSON (with Photos)")
    }

    func testExportJSONWithoutPhotos() throws {
        try export(choosing: "Export as JSON (no Photos)")
    }

    // MARK: - Helpers

    private func export(choosing option: String) throws {
        let catalogueText = app.staticTexts["Test Catalogue"]
        XCTAssertTrue(catalogueText.waitForExistence(timeout: 5))
        catalogueText.tap()
        XCTAssertTrue(app.buttons["Add Item"].waitForExistence(timeout: 3))

        openExportMenu()
        let entry = app.buttons[option]
        XCTAssertTrue(entry.waitForExistence(timeout: 3), "\(option) should be in the Export menu")
        entry.tap()

        // The share sheet only renders once the item has been handed over; give the
        // export time to run, then check the app survived it.
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 10), "Share sheet should appear")
        XCTAssertEqual(app.state, .runningForeground, "App should not crash while exporting")
    }

    private func openExportMenu() {
        // iOS folds secondary actions into the "…" overflow when the bar runs out of room.
        let export = app.buttons["Export"]
        if !export.waitForExistence(timeout: 1) {
            app.buttons["More"].firstMatch.tap()
        }
        XCTAssertTrue(export.waitForExistence(timeout: 3), "Export menu should be reachable")
        export.tap()
    }
}
