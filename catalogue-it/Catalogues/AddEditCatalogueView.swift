//
//  AddEditCatalogueView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

struct AddEditCatalogueView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // If editing an existing catalogue, pass it in
    let catalogue: Catalogue?
    let nextPriority: Int

    // Form state
    @State private var name: String = ""
    @State private var selectedIcon: String = "square.grid.2x2"
    @State private var selectedColor: Color = .blue
    @State private var fieldDefinitions: [FieldDefinitionDraft] = []
    // Off by default; configured in the Options section alongside the status field that
    // gives it meaning.
    @State private var showAllTab: Bool = false
    @State private var showingIconPicker = false
    @State private var showingAddField = false

    // Field deletion confirmation
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var pendingDeleteFieldName = ""
    @State private var pendingDeleteItemCount = 0
    @State private var showingFieldDeleteConfirmation = false

    // Sort-key recompute progress, shown only if the recompute after a structural field
    // change (add/remove/reorder) is still running ~500ms after the save begins.
    @State private var isSavingCatalogue = false
    @State private var sortKeyRecomputeProgress: (current: Int, total: Int)?
    @State private var showSortKeyRecomputeOverlay = false

    private var isEditing: Bool {
        catalogue != nil
    }

    private var hasDuplicateFieldNames: Bool {
        let names = fieldDefinitions.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return names.count != Set(names).count
    }

    init(catalogue: Catalogue? = nil, nextPriority: Int = 0) {
        self.catalogue = catalogue
        self.nextPriority = nextPriority
    }

    var body: some View {
        NavigationStack {
            Form {
                // editMode is set to .active so drag handles appear permanently on field rows
                // MARK: - Basic Info Section
                Section("Catalogue Details") {
                    TextField("Name", text: $name)
#if os(iOS)
                        .textInputAutocapitalization(.words)
#endif
                        .accessibilityIdentifier("catalogue-name-field")

                    // Icon Picker
                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack {
                            Text("Icon")
                            Spacer()
                            Image(systemName: selectedIcon)
                                .font(.title2)
                                .foregroundStyle(selectedColor)
                                .frame(width: 32, height: 32)
                                .background(selectedColor.opacity(0.15))
                                .clipShape(.rect(cornerRadius: 6))
                        }
                    }
                    .foregroundStyle(.primary)

                    // Color Picker
                    ColorPicker("Color", selection: $selectedColor, supportsOpacity: false)
                }

                // MARK: - Field Definitions Section
                Section {
                    ForEach($fieldDefinitions) { $field in
                        FieldDefinitionRow(field: $field, otherFieldNames: otherFieldNames(excluding: field.id))
                    }
                    .onDelete(perform: deleteField)
                    .onMove(perform: moveField)

                    Button {
                        showingAddField = true
                    } label: {
                        Label("Add Field", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Custom Fields")
                } footer: {
                    if hasDuplicateFieldNames {
                        Text("Field names must be unique.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Drag fields to reorder. The first field is used as each item's display name.")
                    }
                }

                // MARK: - Options Section
                // Which fields drive the tab bar and the filter toggles — a catalogue-level
                // decision, so it lives here rather than being set field by field.
                CatalogueOptionsSection(fields: $fieldDefinitions, showAllTab: $showAllTab)
            }
#if os(iOS)
            .environment(\.editMode, .constant(.active))
#endif
            .navigationTitle(isEditing ? "Edit Catalogue" : "New Catalogue")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSavingCatalogue)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        Task { await saveCatalogue() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fieldDefinitions.isEmpty || hasDuplicateFieldNames || isSavingCatalogue)
                }

#if os(iOS)
                ToolbarItem(placement: .principal) {
                    // Show a preview of icon + color
                    Image(systemName: selectedIcon)
                        .foregroundStyle(selectedColor)
                }
#endif
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
            .sheet(isPresented: $showingAddField) {
                FieldEditorView(existingNames: fieldDefinitions.map(\.name)) { field in
                    fieldDefinitions.append(field)
                }
            }
            .confirmationDialog(
                "Delete \"\(pendingDeleteFieldName)\"?",
                isPresented: $showingFieldDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Field", role: .destructive) {
                    if let offsets = pendingDeleteOffsets {
                        fieldDefinitions.remove(atOffsets: offsets)
                    }
                    pendingDeleteOffsets = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteOffsets = nil
                }
            } message: {
                let n = pendingDeleteItemCount
                Text("This field contains data in \(n) item\(n == 1 ? "" : "s"). Deleting it will permanently remove that data when you save. You can still Cancel to keep the field.")
            }
            .onAppear {
                loadCatalogueData()
            }
            .overlay {
                if showSortKeyRecomputeOverlay, let progress = sortKeyRecomputeProgress {
                    ProgressOverlay(
                        current: progress.current,
                        total: progress.total,
                        preparingText: "Updating catalogue…",
                        processingText: { current, total in "Updating \(current) of \(total) items…" }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func loadCatalogueData() {
        guard let catalogue else {
            // Start with some common default fields for new catalogues
            fieldDefinitions = [
                FieldDefinitionDraft(existingDefinition: nil, name: "Name", fieldType: .text, priority: 0)
            ]
            return
        }

        // Load existing catalogue data
        name = catalogue.name
        selectedIcon = catalogue.iconName
        selectedColor = catalogue.color
        showAllTab = catalogue.showAllTab
        fieldDefinitions = catalogue.fieldDefinitions
            .sorted { $0.priority < $1.priority }
            .map {
                FieldDefinitionDraft(
                    existingDefinition: $0,
                    name: $0.name,
                    fieldType: $0.fieldType,
                    priority: $0.priority,
                    displayRole: $0.displayRole,
                    numberOptions: $0.numberOptions ?? NumberOptions(),
                    optionListOptions: $0.optionListOptions ?? OptionListOptions(),
                    booleanOptions: $0.booleanOptions ?? BooleanOptions()
                )
            }
    }

    private func saveCatalogue() async {
        isSavingCatalogue = true
        defer { isSavingCatalogue = false }

        // Normalise before persisting: a role its field type can't support is reset, and any
        // status role beyond the first is dropped. Invalid combinations never reach the store.
        fieldDefinitions = FieldDefinitionValidation.normalised(fieldDefinitions)

        var structuralChange = false
        var facetChange = false
        var itemsNeedingSiblingRecompute: Set<PersistentIdentifier> = []
        var catalogueForRecompute: Catalogue?

        if let existingCatalogue = catalogue {
            // Update existing
            existingCatalogue.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existingCatalogue.iconName = selectedIcon
            existingCatalogue.colorHex = selectedColor.toHex()
            existingCatalogue.showAllTab = showAllTab

            // Captured before any mutation so we can detect an add/remove/reorder below —
            // any such change invalidates every FieldValue's tiebreakKey across the whole
            // catalogue (not just the field that moved), since tiebreakKey encodes "every
            // other field, in priority order".
            let originalFieldIDsInOrder = existingCatalogue.fieldDefinitions
                .sorted { $0.priority < $1.priority }
                .map(\.fieldID)

            // Captured for the same reason, but for the denormalised status/flag columns:
            // they depend on which fields carry a display role and (for status) on the
            // option set, so any change there invalidates every item's facets.
            let originalFacetSignature = Self.facetSignature(of: existingCatalogue.fieldDefinitions)

            // Delete fields that were removed. Snapshot the relationship array first —
            // modelContext.delete(field) mutates it mid-iteration via inverse maintenance.
            // Fetch-and-delete rather than delete(model:where:): the batch delete always
            // throws "mandatory OTO nullify inverse on FieldValue/fieldDefinition" for this
            // schema, silently leaving the removed field's values orphaned on every item.
            let retained = Set(fieldDefinitions.compactMap(\.existingDefinition?.persistentModelID))
            let removedFields = existingCatalogue.fieldDefinitions.filter { !retained.contains($0.persistentModelID) }
            for field in removedFields {
                let fieldID = field.persistentModelID
                let values = (try? modelContext.fetch(FetchDescriptor<FieldValue>(
                    predicate: #Predicate { $0.fieldDefinition?.persistentModelID == fieldID }))) ?? []
                for value in values { modelContext.delete(value) }
                modelContext.delete(field)
            }

            // Update existing fields in-place / insert new fields
            for (index, draft) in fieldDefinitions.enumerated() {
                if let existing = draft.existingDefinition {
                    existing.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)  // rename applied here — no cascade needed
                    existing.priority = index
                    existing.displayRole = draft.displayRole
                    existing.numberOptions = draft.numberOptions
                    existing.optionListOptions = draft.optionListOptions
                    existing.booleanOptions = draft.booleanOptions
                    for (original, current) in draft.pendingOptionRenames where current != original {
                        guard draft.optionListOptions.options.contains(current) else { continue }
                        for fv in existing.fieldValues where fv.fieldType == .optionList && fv.textValue == original {
                            fv.textValue = current
                            fv.sortKey = SortKeyEncoder.sortKey(for: fv)
                            // The renamed value is embedded as a tiebreak segment on every
                            // *other* FieldValue belonging to the same item — flag the item
                            // for a sibling tiebreakKey recompute below.
                            if let item = fv.item { itemsNeedingSiblingRecompute.insert(item.persistentModelID) }
                        }
                    }
                    for deleted in draft.pendingOptionDeletions {
                        for fv in existing.fieldValues where fv.fieldType == .optionList && fv.textValue == deleted {
                            fv.textValue = nil
                            fv.sortKey = SortKeyEncoder.sortKey(for: fv)
                            if let item = fv.item { itemsNeedingSiblingRecompute.insert(item.persistentModelID) }
                        }
                    }
                } else {
                    let field = FieldDefinition(
                        name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        fieldType: draft.fieldType,
                        priority: index,
                        displayRole: draft.displayRole
                    )
                    field.numberOptions = draft.numberOptions
                    field.optionListOptions = draft.optionListOptions
                    field.booleanOptions = draft.booleanOptions
                    field.catalogue = existingCatalogue
                    modelContext.insert(field)
                }
            }

            let newFieldIDsInOrder = fieldDefinitions.compactMap { $0.existingDefinition?.fieldID }
            let hasNewFields = fieldDefinitions.contains { $0.existingDefinition == nil }
            structuralChange = hasNewFields || newFieldIDsInOrder != originalFieldIDsInOrder
            // Compared against the drafts rather than the relationship array: deleted fields
            // linger in `fieldDefinitions` until the save below, so reading the model here
            // would compute a signature that includes fields on their way out.
            facetChange = Self.facetSignature(ofDrafts: fieldDefinitions) != originalFacetSignature
            catalogueForRecompute = existingCatalogue
        } else {
            // Create new
            let newCatalogue = Catalogue(name: name.trimmingCharacters(in: .whitespacesAndNewlines), iconName: selectedIcon, colorHex: selectedColor.toHex(), priority: nextPriority)
            newCatalogue.showAllTab = showAllTab
            modelContext.insert(newCatalogue)

            for (index, draft) in fieldDefinitions.enumerated() {
                let field = FieldDefinition(
                    name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    fieldType: draft.fieldType,
                    priority: index,
                    displayRole: draft.displayRole
                )
                field.numberOptions = draft.numberOptions
                field.optionListOptions = draft.optionListOptions
                field.booleanOptions = draft.booleanOptions
                field.catalogue = newCatalogue
                modelContext.insert(field)
            }
            // Brand new catalogue has no items yet — nothing to recompute.
        }

        // Persist field/priority changes first so the recompute below reads final priorities.
        try? modelContext.save()

        if let catalogueForRecompute {
            if structuralChange || facetChange {
                await recomputeDerivedDataWithDelayedOverlay(
                    for: catalogueForRecompute,
                    tiebreakKeys: structuralChange,
                    facets: facetChange
                )
                if !structuralChange && !itemsNeedingSiblingRecompute.isEmpty {
                    // The full sweep above only rebuilt facets, so sibling tiebreak keys
                    // invalidated by an option rename/delete still need their own pass.
                    recomputeSiblingTiebreakKeys(for: catalogueForRecompute, itemIDs: itemsNeedingSiblingRecompute)
                    try? modelContext.save()
                }
            } else if !itemsNeedingSiblingRecompute.isEmpty {
                // Cheap, bounded by how many items reference the renamed/deleted option
                // value — no chunking needed (the full-catalogue path above already covers
                // every item when a structural change also occurred, so this is skipped then).
                recomputeSiblingTiebreakKeys(for: catalogueForRecompute, itemIDs: itemsNeedingSiblingRecompute)
                try? modelContext.save()
            }
        }

        dismiss()
    }

    /// A stable description of everything the denormalised status/flag columns depend on.
    /// Comparing it before and after a save detects role changes, option renames/removals,
    /// and role-carrying fields being added or deleted — all of which invalidate every
    /// item's facets even though no item was edited.
    private static func facetSignature(of fields: [FieldDefinition]) -> String {
        signature(from: fields.map {
            (
                id: $0.fieldID.uuidString,
                role: $0.displayRole,
                type: $0.fieldType,
                options: $0.optionListOptions?.options ?? []
            )
        })
    }

    /// Draft-side counterpart. New fields have no `fieldID` yet, so their index stands in —
    /// any newly added role-carrying field changes the signature either way.
    private static func facetSignature(ofDrafts drafts: [FieldDefinitionDraft]) -> String {
        signature(from: drafts.enumerated().map { index, draft in
            (
                id: draft.existingDefinition?.fieldID.uuidString ?? "new-\(index)",
                role: draft.displayRole,
                type: draft.fieldType,
                options: draft.optionListOptions.options
            )
        })
    }

    private static func signature(
        from fields: [(id: String, role: DisplayRole, type: FieldType, options: [String])]
    ) -> String {
        fields
            .filter { $0.role != .none }
            .sorted { $0.id < $1.id }
            .map { "\($0.id)\u{1E}\($0.role.rawValue)\u{1E}\($0.type.rawValue)\u{1E}\($0.options.joined(separator: "\u{1F}"))" }
            .joined(separator: "\u{1D}")
    }

    /// Runs the full-catalogue recompute, showing `ProgressOverlay` only if it's still
    /// running ~500ms after starting — so a fast recompute on a small catalogue shows
    /// nothing, while a large one gets clear feedback instead of the sheet appearing to hang.
    private func recomputeDerivedDataWithDelayedOverlay(
        for catalogue: Catalogue,
        tiebreakKeys: Bool,
        facets: Bool
    ) async {
        sortKeyRecomputeProgress = (current: 0, total: 0)
        let overlayDelay = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled {
                showSortKeyRecomputeOverlay = true
            }
        }

        await CatalogueSortKeyMaintenance.recomputeDerivedData(
            for: catalogue,
            in: modelContext,
            tiebreakKeys: tiebreakKeys,
            facets: facets,
            onProgress: { current, total in sortKeyRecomputeProgress = (current: current, total: total) }
        )

        overlayDelay.cancel()
        showSortKeyRecomputeOverlay = false
        sortKeyRecomputeProgress = nil
    }

    /// Recomputes tiebreakKey for every FieldValue on the given items — used when an
    /// option-list value is renamed or deleted, since that value is embedded as a tiebreak
    /// segment on sibling FieldValues for the same items.
    private func recomputeSiblingTiebreakKeys(for catalogue: Catalogue, itemIDs: Set<PersistentIdentifier>) {
        let sortedDefs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }
        for itemID in itemIDs {
            guard let item = modelContext.model(for: itemID) as? CatalogueItem else { continue }
            let itemFieldValues = item.fieldValues
            for fv in itemFieldValues {
                fv.tiebreakKey = SortKeyEncoder.tiebreakKey(
                    for: fv,
                    allFieldValuesOnItem: itemFieldValues,
                    fieldDefinitionsByPriority: sortedDefs,
                    itemCreatedDate: item.createdDate
                )
            }
        }
    }

    /// Every other field's name, so the editor flags a clash without flagging the field
    /// against itself when its name is left alone.
    private func otherFieldNames(excluding id: UUID) -> [String] {
        fieldDefinitions.filter { $0.id != id }.map(\.name)
    }

    private func deleteField(at offsets: IndexSet) {
        let affectedFields = offsets.map { fieldDefinitions[$0] }
        let totalDataCount = affectedFields.reduce(0) { $0 + itemDataCount(for: $1) }

        if totalDataCount > 0 {
            pendingDeleteOffsets = offsets
            pendingDeleteFieldName = affectedFields.first?.name ?? ""
            pendingDeleteItemCount = totalDataCount
            showingFieldDeleteConfirmation = true
        } else {
            fieldDefinitions.remove(atOffsets: offsets)
        }
    }

    private func itemDataCount(for draft: FieldDefinitionDraft) -> Int {
        guard let field = draft.existingDefinition else { return 0 }
        return field.fieldValues.count { fv in
            switch fv.fieldType {
            case .text, .optionList: return fv.textValue != nil
            case .number:            return fv.numberValue != nil
            case .date:              return fv.dateValue != nil
            case .boolean:           return fv.boolValue == true
            }
        }
    }

    private func moveField(from source: IndexSet, to destination: Int) {
        fieldDefinitions.move(fromOffsets: source, toOffset: destination)
        // Update sort order
        for (index, _) in fieldDefinitions.enumerated() {
            fieldDefinitions[index].priority = index
        }
    }
}

// MARK: - Preview

#Preview("New Catalogue") {
    AddEditCatalogueView()
        .modelContainer(for: Catalogue.self, inMemory: true)
}
