//
//  ImportCommands.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Import Commands

/// File ▸ Import from File… and Paste from Spreadsheet, in the iPad menu bar and on a Mac.
struct ImportCommands: Commands {
    @FocusedValue(\.importAction) private var importAction

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Import from File…") { importAction?(.file) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(importAction == nil)
            Button("Paste from Spreadsheet") { importAction?(.paste) }
                .disabled(importAction == nil)
        }
    }
}
