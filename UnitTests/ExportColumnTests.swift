//
//  ExportColumnTests.swift
//  UnitTests
//

import Testing
import Foundation
@testable import catalogue_it

// MARK: - Export Column Tests

@MainActor
struct ExportColumnTests {

    private func makeCatalogue() -> (Catalogue, [FieldDefinition]) {
        let catalogue = Catalogue(name: "Planes")
        // Added out of order: columns follow priority, not insertion.
        let second = FieldDefinition(name: "Year", fieldType: .number, priority: 1)
        let first = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        catalogue.fieldDefinitions = [second, first]
        return (catalogue, [first, second])
    }

    @Test("Message and card list fields then Notes; a spreadsheet adds Date Added and Photo Count")
    func columnsPerFormat() {
        let (catalogue, fields) = makeCatalogue()
        let fieldColumns = fields.map { ExportColumn.field($0.fieldID) }
        #expect(ExportFormat.message.columns(for: catalogue) == fieldColumns + [.notes])
        #expect(ExportFormat.card.columns(for: catalogue) == fieldColumns + [.notes])
        #expect(ExportFormat.spreadsheet.columns(for: catalogue) == fieldColumns + [.notes, .dateAdded, .photoCount])
    }

    @Test("The first field is locked for message and card only")
    func lockedColumn() {
        let (catalogue, fields) = makeCatalogue()
        #expect(ExportFormat.message.lockedColumn(for: catalogue) == .field(fields[0].fieldID))
        #expect(ExportFormat.card.lockedColumn(for: catalogue) == .field(fields[0].fieldID))
        #expect(ExportFormat.spreadsheet.lockedColumn(for: catalogue) == nil)
        #expect(ExportFormat.message.lockedColumn(for: Catalogue(name: "Empty")) == nil)
    }

    @Test("Field columns are titled by the field's name")
    func titles() {
        let (catalogue, fields) = makeCatalogue()
        #expect(ExportColumn.field(fields[1].fieldID).title(in: catalogue) == "Year")
    }
}
