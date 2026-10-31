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

    let catalogue: Catalogue?
    let nextPriority: Int
    /// So a new catalogue can start on a colour not already taken. Ignored when editing.
    let existingColorHexes: [String]

    @State private var name: String = ""
    @State private var selectedIcon: String = "square.grid.2x2"
    @State private var selectedColor: Color = .blue
    @State private var fieldDefinitions: [FieldDefinitionDraft] = []
    @State private var showAllTab: Bool = false
    @State private var layoutOptions = CatalogueLayoutOptions()
    @State private var showingIconPicker = false
    @State private var showingAddField = false
    @State private var baseline: Baseline?

    private struct Baseline {
        var name: String
        var iconName: String
        var color: Color
        var showAllTab: Bool
        var layoutOptions: CatalogueLayoutOptions
        var fieldDefinitions: [FieldDefinitionDraft]
    }

    private var hasChanges: Bool {
        guard let baseline else { return false }
        return name != baseline.name
            || selectedIcon != baseline.iconName
            || selectedColor != baseline.color
            || showAllTab != baseline.showAllTab
            || layoutOptions != baseline.layoutOptions
            || !fieldDefinitions.hasSameContent(as: baseline.fieldDefinitions)
    }
    @State private var isReorderingFields = false

    @State private var pendingDeleteOffsets: IndexSet?
    @State private var pendingDeleteFieldName = ""
    @State private var pendingDeleteItemCount = 0
    @State private var showingFieldDeleteConfirmation = false

    // Shown only if the recompute is still running ~500ms after the save begins.
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

    init(catalogue: Catalogue? = nil, nextPriority: Int = 0, existingColorHexes: [String] = []) {
        self.catalogue = catalogue
        self.nextPriority = nextPriority
        self.existingColorHexes = existingColorHexes
    }

    var body: some View {
        NavigationStack {
            Form {
                CatalogueHeaderSection(
                    name: $name,
                    iconName: selectedIcon,
                    color: $selectedColor,
                    onChangeIcon: { showingIconPicker = true }
                )

                // MARK: - Field Definitions Section
                Section {
                    ForEach($fieldDefinitions) { $field in
                        FieldDefinitionRow(
                            field: $field,
                            otherFieldNames: otherFieldNames(excluding: field.id),
                            previewContext: fieldPreviewContext(for: field.id),
                            onDelete: { deleteField(withID: field.id) }
                        )
                    }
                    .onDelete(perform: deleteField)
                    .onMove(perform: moveField)

                    if !isReorderingFields {
                        Button {
                            showingAddField = true
                        } label: {
                            Label("Add Field", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    HStack {
                        Text("Fields")
                        Spacer()
                        // A mode, not the resting state: edit mode suppresses the rows' swipe actions. Stays
                        // visible with one field left, so there's always a way out.
                        if fieldDefinitions.count > 1 || isReorderingFields {
                            Button(isReorderingFields ? "Done" : "Reorder") {
                                withAnimation { isReorderingFields.toggle() }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                } footer: {
                    if hasDuplicateFieldNames {
                        Text("Field names must be unique.")
                            .foregroundStyle(.red)
                    } else if isReorderingFields {
                        Text("Drag fields to reorder. The first field is used as each item's display name.")
                    } else {
                        Text("The first field is each item's name. Tap a field to change its settings, or swipe it for more.")
                    }
                }

                ItemListSettingsSection(
                    fields: $fieldDefinitions,
                    showAllTab: $showAllTab,
                    layoutOptions: $layoutOptions,
                    colorHex: selectedColor.toHex()
                )
            }
#if os(iOS)
            .environment(\.editMode, .constant(isReorderingFields ? .active : .inactive))
#endif
            .navigationTitle(isEditing ? "Edit Catalogue" : "New Catalogue")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .disabled(isSavingCatalogue)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create", systemImage: "checkmark") {
                        Task { await saveCatalogue() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fieldDefinitions.isEmpty || hasDuplicateFieldNames || isSavingCatalogue)
                }

#if os(iOS)
                ToolbarItem(placement: .principal) {
                    CatalogueIconView(iconName: selectedIcon, color: selectedColor, size: 17)
                }
#endif
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon, tint: selectedColor)
            }
            .sheet(isPresented: $showingAddField) {
                FieldEditorView(
                    existingNames: fieldDefinitions.map(\.name),
                    previewContext: fieldPreviewContext(for: nil)
                ) { field in
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
            // A swipe-down or tap outside would silently drop edits.
            .interactiveDismissDisabled(hasChanges)
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
        guard baseline == nil else { return }
        defer {
            baseline = Baseline(
                name: name,
                iconName: selectedIcon,
                color: selectedColor,
                showAllTab: showAllTab,
                layoutOptions: layoutOptions,
                fieldDefinitions: fieldDefinitions
            )
        }

        guard let catalogue else {
            selectedColor = Color(hex: CatalogueColorSuggester.suggestedHex(avoiding: existingColorHexes))
            fieldDefinitions = [
                FieldDefinitionDraft(existingDefinition: nil, name: "Name", fieldType: .text, priority: 0)
            ]
            return
        }

        name = catalogue.name
        selectedIcon = catalogue.iconName
        selectedColor = catalogue.color
        showAllTab = catalogue.showAllTab
        layoutOptions = catalogue.layoutOptions
        fieldDefinitions = catalogue.sortedFieldDefinitions
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

        fieldDefinitions = FieldDefinitionValidation.normalised(fieldDefinitions)

        var structuralChange = false
        var facetChange = false
        var itemsNeedingSiblingRecompute: Set<PersistentIdentifier> = []
        var catalogueForRecompute: Catalogue?

        if let existingCatalogue = catalogue {
            existingCatalogue.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existingCatalogue.iconName = selectedIcon
            existingCatalogue.colorHex = selectedColor.toHex()
            existingCatalogue.showAllTab = showAllTab
            existingCatalogue.layoutOptions = layoutOptions

            // An add, remove or reorder invalidates every tiebreakKey in the catalogue, which encodes
            // every other field in priority order.
            let originalFieldIDsInOrder = existingCatalogue.sortedFieldDefinitions
                .map(\.fieldID)

            // Likewise for the status/flag columns, which depend on roles and the status option set.
            let originalFacetSignature = Self.facetSignature(of: existingCatalogue.fieldDefinitions)

            // Snapshot first: deleting mutates the relationship mid-iteration. Fetch-and-delete, not
            // delete(model:where:), which throws "mandatory OTO nullify inverse" here and leaves the
            // values orphaned.
            let retained = Set(fieldDefinitions.compactMap(\.existingDefinition?.persistentModelID))
            let removedFields = existingCatalogue.fieldDefinitions.filter { !retained.contains($0.persistentModelID) }
            for field in removedFields {
                let fieldID = field.persistentModelID
                let values = (try? modelContext.fetch(FetchDescriptor<FieldValue>(
                    predicate: #Predicate { $0.fieldDefinition?.persistentModelID == fieldID }))) ?? []
                for value in values { modelContext.delete(value) }
                modelContext.delete(field)
            }

            for (index, draft) in fieldDefinitions.enumerated() {
                if let existing = draft.existingDefinition {
                    existing.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    existing.priority = index
                    existing.displayRole = draft.displayRole
                    // `fieldOptions` syncs, so an equal value rewritten on every field exports every one.
                    if existing.numberOptions != draft.numberOptions {
                        existing.numberOptions = draft.numberOptions
                    }
                    if existing.optionListOptions != draft.optionListOptions {
                        existing.optionListOptions = draft.optionListOptions
                    }
                    if existing.booleanOptions != draft.booleanOptions {
                        existing.booleanOptions = draft.booleanOptions
                    }
                    for (original, current) in draft.pendingOptionRenames where current != original {
                        guard draft.optionListOptions.options.contains(current) else { continue }
                        for fv in existing.fieldValues where fv.fieldType == .optionList && fv.textValue == original {
                            fv.textValue = current
                            fv.sortKey = SortKeyEncoder.sortKey(for: fv)
                            // The value is a tiebreak segment on the item's other FieldValues.
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
            // From the drafts: deleted fields linger in `fieldDefinitions` until the save.
            facetChange = Self.facetSignature(ofDrafts: fieldDefinitions) != originalFacetSignature
            catalogueForRecompute = existingCatalogue
        } else {
            let newCatalogue = Catalogue(name: name.trimmingCharacters(in: .whitespacesAndNewlines), iconName: selectedIcon, colorHex: selectedColor.toHex(), priority: nextPriority)
            newCatalogue.showAllTab = showAllTab
            newCatalogue.layoutOptions = layoutOptions
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
        }

        // Save first so the recompute reads final priorities.
        try? modelContext.save()

        if let catalogueForRecompute {
            if structuralChange || facetChange {
                // Covers the sibling tiebreak keys an option rename or delete invalidates too.
                await recomputeDerivedDataWithDelayedOverlay(for: catalogueForRecompute)
            } else if !itemsNeedingSiblingRecompute.isEmpty {
                // Bounded by the items holding the renamed or deleted option.
                recomputeSiblingTiebreakKeys(for: catalogueForRecompute, itemIDs: itemsNeedingSiblingRecompute)
                try? modelContext.save()
            }
        }

        dismiss()
    }

    /// Changes with roles, option renames and removals, and role-carrying fields coming and
    /// going — each invalidates every item's facets though no item was edited.
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

    /// New fields have no `fieldID` yet, so their index stands in.
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

    /// Shows `ProgressOverlay` only if still running after ~500ms.
    private func recomputeDerivedDataWithDelayedOverlay(for catalogue: Catalogue) async {
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
            onProgress: { current, total in sortKeyRecomputeProgress = (current: current, total: total) }
        )

        overlayDelay.cancel()
        showSortKeyRecomputeOverlay = false
        sortKeyRecomputeProgress = nil
    }

    /// For an option rename or delete: the value is the item's sort key, part of its search
    /// text, and a tiebreak segment on its sibling FieldValues.
    private func recomputeSiblingTiebreakKeys(for catalogue: Catalogue, itemIDs: Set<PersistentIdentifier>) {
        let sortedDefs = catalogue.sortedFieldDefinitions
        for itemID in itemIDs {
            guard let item = modelContext.model(for: itemID) as? CatalogueItem else { continue }
            ItemDerivedColumns.refresh(on: item, fieldValues: item.fieldValues, definitions: sortedDefs)
        }
    }

    /// Excludes the field's own name, so keeping it isn't a clash.
    private func otherFieldNames(excluding id: UUID) -> [String] {
        fieldDefinitions.filter { $0.id != id }.map(\.name)
    }

    /// `nil` for a field being added, which goes at the end.
    private func fieldPreviewContext(for id: UUID?) -> FieldPreviewContext {
        let index = id.flatMap { id in fieldDefinitions.firstIndex { $0.id == id } } ?? fieldDefinitions.endIndex
        return FieldPreviewContext(
            fieldsBefore: Array(fieldDefinitions[..<index]),
            fieldsAfter: Array(fieldDefinitions[min(index + 1, fieldDefinitions.endIndex)...]),
            layoutOptions: layoutOptions,
            tint: selectedColor
        )
    }

    /// Through the list's offset-based path, so a field holding data still gets confirmation.
    private func deleteField(withID id: UUID) {
        guard let index = fieldDefinitions.firstIndex(where: { $0.id == id }) else { return }
        deleteField(at: IndexSet(integer: index))
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
