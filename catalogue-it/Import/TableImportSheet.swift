//
//  TableImportSheet.swift
//  catalogue-it
//

import SwiftData
import SwiftUI

// MARK: - Table Import Sheet

/// Imports a spreadsheet: where it goes, which field each column fills, then a review of what
/// will be created and which values can't be read.
struct TableImportSheet: View {
    let catalogues: [Catalogue]
    /// The catalogue to write, where, and how many rows were left out as already there.
    let onImport: (CatalogueDTO, ImportDestination, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: TableImportModel
    @State private var review: TableImportPlanner.Built?

    init(table: ImportTable, sourceName: String, catalogues: [Catalogue],
         initialDestination: ImportDestination? = nil,
         onImport: @escaping (CatalogueDTO, ImportDestination, Int) -> Void) {
        self.catalogues = catalogues
        self.onImport = onImport
        let model = TableImportModel(table: table, sourceName: sourceName)
        if let initialDestination, case .existing(let id) = initialDestination,
           let catalogue = catalogues.first(where: { $0.persistentModelID == id }) {
            model.setDestination(initialDestination, fields: catalogue.sortedFieldDefinitions.map(TargetField.init))
        }
        _model = State(initialValue: model)
    }

    private var target: Catalogue? {
        guard case .existing(let id) = model.destination else { return nil }
        return catalogues.first { $0.persistentModelID == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                optionsSection
                columnsSection
                if let target, !model.duplicateCandidates.isEmpty {
                    duplicatesSection(for: target)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import Spreadsheet")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        review = model.build(colorHex: CatalogueColorSuggester.suggestedHex(avoiding: catalogues.map(\.colorHex)))
                    }
                    .disabled(model.importedColumnCount == 0)
                }
            }
            .navigationDestination(isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
                if let built = review {
                    TableImportReview(model: model, built: built, catalogueName: target?.name ?? built.catalogue.name) {
                        onImport(built.catalogue, model.destination, built.duplicateRowCount)
                        dismiss()
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
#endif
    }

    // MARK: Sections

    private var destinationSection: some View {
        Section {
            Picker("Import Into", selection: Binding(
                get: { model.destination },
                set: { destination in
                    let fields: [TargetField]
                    if case .existing(let id) = destination,
                       let catalogue = catalogues.first(where: { $0.persistentModelID == id }) {
                        fields = catalogue.sortedFieldDefinitions.map(TargetField.init)
                    } else {
                        fields = []
                    }
                    model.setDestination(destination, fields: fields)
                }
            )) {
                Text("New Catalogue").tag(ImportDestination.newCatalogue)
                if !catalogues.isEmpty {
                    Divider()
                    ForEach(catalogues) { catalogue in
                        Text(catalogue.name).tag(ImportDestination.existing(catalogue.persistentModelID))
                    }
                }
            }
            if model.destination == .newCatalogue {
                TextField("Name", text: $model.catalogueName)
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("First Row Is Column Names", isOn: $model.hasHeaderRow)
            if model.asksForDateOrder {
                Picker("Dates", selection: $model.dateOrder) {
                    Text("Day/Month/Year").tag(ImportDateOrder.dayMonthYear)
                    Text("Month/Day/Year").tag(ImportDateOrder.monthDayYear)
                }
            }
        } footer: {
            Text("\(TableImportPlanner.dataRows(of: model.table, hasHeaderRow: model.hasHeaderRow).count) rows")
        }
    }

    private func duplicatesSection(for target: Catalogue) -> some View {
        Section {
            Picker("Skip Rows Already Here", selection: Binding(
                get: { model.duplicateCheck?.column },
                set: { column in
                    guard let column, let field = model.duplicateCandidates.first(where: { $0.column == column })?.field,
                          let definition = target.fieldDefinitions.first(where: { $0.fieldID == field.fieldID }) else {
                        model.setDuplicateCheck(nil)
                        return
                    }
                    let keys = definition.fieldValues
                        .filter { $0.item != nil && $0.item?.deletedDate == nil }
                        .compactMap(TableImportPlanner.duplicateKey)
                    model.setDuplicateCheck(column: column, existingKeys: Set(keys))
                }
            )) {
                Text("Import Every Row").tag(Int?.none)
                ForEach(model.duplicateCandidates, id: \.column) { candidate in
                    Text("Same \(candidate.field.name)").tag(Int?.some(candidate.column))
                }
            }
        } header: {
            Text("Duplicates")
        } footer: {
            if let check = model.duplicateCheck,
               let name = model.duplicateCandidates.first(where: { $0.column == check.column })?.field.name {
                Text("^[\(model.duplicateRowCount) row](inflect: true) share a \(name) with an item already in “\(target.name)” and will be left out.")
            } else {
                Text("Choose a field that identifies an item, such as a name or number, to leave out rows already in “\(target.name)”.")
            }
        }
    }

    private var columnsSection: some View {
        Section {
            ForEach(model.columns) { column in
                ColumnMappingRow(
                    column: column,
                    target: Binding(
                        get: { model.targets[column.index] },
                        set: { model.setTarget($0, forColumn: column.index) }
                    ),
                    check: model.checks.indices.contains(column.index) ? model.checks[column.index] : ColumnCheck(),
                    existing: model.existing,
                    catalogueName: target?.name
                )
            }
        } header: {
            Text("Columns")
        } footer: {
            if target != nil {
                Text("Columns are matched to fields by name. New fields are added after the catalogue’s own.")
            }
        }
    }
}

// MARK: - Column Mapping Row

private struct ColumnMappingRow: View {
    let column: ColumnSummary
    @Binding var target: ColumnTarget
    let check: ColumnCheck
    let existing: [TargetField]
    let catalogueName: String?

    /// The menu sits beside the column name, with samples and warnings beneath at full width:
    /// as a Form picker's label they would push the menu onto its own line in some rows only.
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(column.header)
                    .lineLimit(2)
                Spacer(minLength: 8)
                picker
                    .labelsHidden()
                    .fixedSize()
            }
            if !column.samples.isEmpty {
                Text(column.samples.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if check.unreadableCount > 0 {
                Label("^[\(check.unreadableCount) value](inflect: true) can’t be read and will be left empty",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var picker: some View {
        Picker(column.header, selection: $target) {
            Text("Don’t Import").tag(ColumnTarget.skip)
            Section("Item") {
                Label("Notes", systemImage: "note.text").tag(ColumnTarget.notes)
                Label("Date Added", systemImage: "calendar.badge.plus").tag(ColumnTarget.dateAdded)
            }
            if let catalogueName, !existing.isEmpty {
                Section("Fields in “\(catalogueName)”") {
                    ForEach(existing, id: \.fieldID) { field in
                        Label(field.name, systemImage: field.fieldType.icon).tag(ColumnTarget.field(field.fieldID))
                    }
                }
            }
            Section("New Field") {
                ForEach(FieldType.allCases, id: \.self) { type in
                    Label("New \(type.rawValue) Field", systemImage: type.icon).tag(ColumnTarget.newField(type))
                }
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Review

private struct TableImportReview: View {
    let model: TableImportModel
    let built: TableImportPlanner.Built
    let catalogueName: String
    let onImport: () -> Void

    private var newFields: [FieldDefinitionDTO] {
        let existingIDs = Set(model.existing.map(\.fieldID))
        return built.catalogue.fieldDefinitions.filter { !existingIDs.contains($0.fieldID) }
    }

    private var problemColumns: [(column: ColumnSummary, check: ColumnCheck)] {
        model.columns.compactMap { column in
            let check = model.checks[column.index]
            return check.unreadableCount > 0 ? (column, check) : nil
        }
    }

    private var optionAdditions: [(field: TargetField, options: [String])] {
        model.columns.compactMap { column in
            guard case .field(let id) = model.targets[column.index],
                  let field = model.existing.first(where: { $0.fieldID == id }),
                  !model.checks[column.index].newOptions.isEmpty else { return nil }
            return (field, model.checks[column.index].newOptions)
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Items", value: built.catalogue.items.count.formatted())
                LabeledContent(model.destination == .newCatalogue ? "New Catalogue" : "Into", value: catalogueName)
                if built.duplicateRowCount > 0 {
                    LabeledContent("Already Here, Skipped", value: built.duplicateRowCount.formatted())
                }
                if built.skippedRowCount > 0 {
                    LabeledContent("Empty Rows Skipped", value: built.skippedRowCount.formatted())
                }
            }

            if !newFields.isEmpty {
                Section("New Fields") {
                    ForEach(newFields, id: \.fieldID) { field in
                        LabeledContent {
                            Text(field.fieldType.rawValue)
                        } label: {
                            Label(field.name, systemImage: field.fieldType.icon)
                        }
                    }
                }
            }

            if !optionAdditions.isEmpty {
                Section("New Options") {
                    ForEach(optionAdditions, id: \.field.fieldID) { addition in
                        LabeledContent(addition.field.name) {
                            Text(addition.options.joined(separator: ", "))
                                .lineLimit(2)
                        }
                    }
                }
            }

            if !problemColumns.isEmpty {
                Section {
                    ForEach(problemColumns, id: \.column.id) { problem in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(problem.column.header)
                            Text("^[\(problem.check.unreadableCount) value](inflect: true), such as \(problem.check.examples.map { "“\($0)”" }.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Values Left Empty")
                } footer: {
                    Text("These can’t be read as their field’s type. Go back to choose another field or type for the column.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Review")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Import", action: onImport)
                    .disabled(built.catalogue.items.isEmpty)
            }
        }
    }
}
