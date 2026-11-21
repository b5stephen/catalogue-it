//
//  ImportDestinationSheet.swift
//  catalogue-it
//

import SwiftData
import SwiftUI

// MARK: - Import Destination

enum ImportDestination: Hashable {
    case newCatalogue
    case existing(PersistentIdentifier)
}

// MARK: - Import Destination Sheet

/// Asks where a one-catalogue Data file goes: a new catalogue, as before, or into an existing
/// one, previewing how its fields match and how many of its items are already there.
struct ImportDestinationSheet: View {
    let file: CatalogueDTO
    let catalogues: [Catalogue]
    let onImport: (ImportDestination, _ skippingDuplicates: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var destination: ImportDestination
    @State private var skipsDuplicates = true
    @State private var duplicateCount = 0

    init(
        file: CatalogueDTO,
        catalogues: [Catalogue],
        initialDestination: ImportDestination? = nil,
        onImport: @escaping (ImportDestination, _ skippingDuplicates: Bool) -> Void
    ) {
        self.file = file
        self.catalogues = catalogues
        self.onImport = onImport
        _destination = State(initialValue: initialDestination ?? .newCatalogue)
    }

    private var target: Catalogue? {
        guard case .existing(let id) = destination else { return nil }
        return catalogues.first { $0.persistentModelID == id }
    }

    private var hasPhotos: Bool {
        file.items.contains { !$0.photos.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Catalogue", value: file.name)
                    LabeledContent("Items", value: file.items.count.formatted())
                    LabeledContent("Fields", value: file.fieldDefinitions.count.formatted())
                    if hasPhotos {
                        LabeledContent("Photos", value: String(localized: "Included"))
                    }
                } header: {
                    Text("File")
                }

                Section {
                    Picker("Import Into", selection: $destination) {
                        Text("New Catalogue").tag(ImportDestination.newCatalogue)
                        ForEach(catalogues) { catalogue in
                            Text(catalogue.name).tag(ImportDestination.existing(catalogue.persistentModelID))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Import Into")
                }

                if let target {
                    fieldsSection(for: target)
                    if duplicateCount > 0 {
                        duplicatesSection(for: target)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import Catalogue")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(destination, skipsDuplicates && duplicateCount > 0)
                        dismiss()
                    }
                    .disabled(target == nil && destination != .newCatalogue)
                }
            }
            .task(id: destination) { countDuplicates() }
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
#endif
    }

    // MARK: Sections

    private func fieldsSection(for target: Catalogue) -> some View {
        let entries = ImportFieldMatcher.match(
            file.fieldDefinitions,
            to: target.fieldDefinitions.map(ImportFieldMatcher.ExistingField.init)
        )
        let addsFields = entries.contains { if case .new = $0.match { true } else { false } }
        return Section {
            ForEach(entries) { entry in
                LabeledContent {
                    switch entry.match {
                    case .existing(_, let name):
                        Text(name)
                    case .new(let name):
                        Text("New Field “\(name)”")
                    }
                } label: {
                    Label(entry.name, systemImage: entry.fieldType.icon)
                }
            }
        } header: {
            Text("Fields")
        } footer: {
            if addsFields {
                Text("New fields are added to “\(target.name)” after its own.")
            }
        }
    }

    private func duplicatesSection(for target: Catalogue) -> some View {
        Section {
            Toggle("Skip Items Already Here", isOn: $skipsDuplicates)
        } footer: {
            Text("\(duplicateCount) of the file’s \(file.items.count) items are already in “\(target.name)”, from an earlier export or import.")
        }
    }

    private func countDuplicates() {
        guard let target else {
            duplicateCount = 0
            return
        }
        let existing = (try? ItemImporter.liveCreatedDates(of: target.persistentModelID, in: modelContext)) ?? []
        duplicateCount = file.items.count { existing.contains($0.createdDate) }
    }
}
