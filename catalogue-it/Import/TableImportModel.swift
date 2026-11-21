//
//  TableImportModel.swift
//  catalogue-it
//

import Foundation
import Observation

// MARK: - Table Import Model

/// The column-mapping sheet's state. Column guesses and value checks are recomputed only when
/// what they depend on changes, as a large sheet takes a moment to scan.
@Observable
final class TableImportModel {
    let table: ImportTable
    private let parser = ImportValueParser()

    var destination = ImportDestination.newCatalogue
    var catalogueName: String

    var hasHeaderRow: Bool {
        didSet { if hasHeaderRow != oldValue { rebuildColumns() } }
    }
    var dateOrder: ImportDateOrder {
        didSet {
            parser.dateOrder = dateOrder
            if dateOrder != oldValue { rebuildChecks() }
        }
    }

    private(set) var columns: [ColumnSummary] = []
    private(set) var targets: [ColumnTarget] = []
    private(set) var checks: [ColumnCheck] = []
    private(set) var existing: [TargetField] = []
    /// Shown only when the sheet has numeric dates whose values don't settle the order.
    private(set) var asksForDateOrder = false

    init(table: ImportTable, sourceName: String) {
        self.table = table
        catalogueName = sourceName
        hasHeaderRow = TableImportPlanner.guessHasHeaderRow(table, parser: parser)
        dateOrder = parser.dateOrder
        rebuildColumns()
    }

    func setDestination(_ destination: ImportDestination, fields: [TargetField]) {
        self.destination = destination
        existing = fields
        targets = TableImportPlanner.defaultTargets(for: columns, existing: existing)
        rebuildChecks()
    }

    /// Notes, Date Added and an existing field take one column; the column that had it is
    /// skipped instead.
    func setTarget(_ target: ColumnTarget, forColumn index: Int) {
        if target.isExclusive, let other = targets.firstIndex(of: target), other != index {
            targets[other] = .skip
            checks[other] = check(column: other)
        }
        targets[index] = target
        checks[index] = check(column: index)
    }

    var importedColumnCount: Int {
        targets.count { $0 != .skip }
    }

    func build(colorHex: String) -> TableImportPlanner.Built {
        let name = catalogueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = TableImportPlanner.Plan(
            hasHeaderRow: hasHeaderRow,
            targets: targets,
            catalogueName: name.isEmpty ? String(localized: "Imported Catalogue") : name,
            colorHex: colorHex
        )
        return TableImportPlanner.build(table, plan: plan, existing: existing, parser: parser)
    }

    // MARK: Recomputing

    private func rebuildColumns() {
        columns = TableImportPlanner.summarise(table, hasHeaderRow: hasHeaderRow, parser: parser)
        if let implied = TableImportPlanner.impliedDateOrder(table, hasHeaderRow: hasHeaderRow, parser: parser) {
            asksForDateOrder = false
            if implied != dateOrder { dateOrder = implied }
        } else {
            asksForDateOrder = TableImportPlanner.hasAmbiguousDates(table, hasHeaderRow: hasHeaderRow, parser: parser)
        }
        targets = TableImportPlanner.defaultTargets(for: columns, existing: existing)
        rebuildChecks()
    }

    private func rebuildChecks() {
        guard targets.count == columns.count else { return }
        checks = columns.indices.map(check(column:))
    }

    private func check(column index: Int) -> ColumnCheck {
        TableImportPlanner.check(
            table, column: index, target: targets[index], hasHeaderRow: hasHeaderRow,
            existing: existing, parser: parser)
    }
}
