//
//  AddEditItemView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Add Edit Item View

struct AddEditItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let catalogue: Catalogue
    let existingItem: CatalogueItem?
    let duplicateSource: CatalogueItem?
    /// The tab the user was viewing; `nil` uses the status field's own default.
    let defaultStatusTab: StatusTab?

    // MARK: - Form State

    @State private var sortedDefs: [FieldDefinition] = []
    @State private var fieldDrafts: [FieldValueDraft] = []
    @State private var photoDrafts: [PhotoDraft] = []
    @State private var notes: String = ""
    @State private var previewPhotoID: UUID? = nil
    @State private var hasLoaded: Bool = false
    /// Keeps the sheet open, drafts intact, after a failed save.
    @State private var saveError: Error?
    @State private var isSaving = false
    /// The form as loaded. Unlike `baseline` it is set when duplicating too, where the save
    /// must write every pre-filled value.
    @State private var loadedPhotoDrafts: [PhotoDraft] = []
    @State private var loadedFieldDrafts: [FieldValueDraft] = []
    @State private var loadedNotes: String = ""
    /// Set only when editing — see `EditBaseline`.
    @State private var baseline: EditBaseline?
    @FocusState private var isNotesFocused: Bool

    private let notesFieldID = "notesField"

    // MARK: - Computed

    private var isEditing: Bool { existingItem != nil }

    /// A duplicate's pre-filled values and a new item's default status don't count until touched.
    private var hasChanges: Bool {
        guard hasLoaded else { return false }
        return notes != loadedNotes
            || photoDrafts != loadedPhotoDrafts
            || fieldDrafts.count != loadedFieldDrafts.count
            || !zip(fieldDrafts, loadedFieldDrafts).allSatisfy { $0.hasSameValue(as: $1) }
    }

    // Booleans always have a value, and status and flag fields start at their defaults, so none
    // of them make an item non-empty.
    private var hasNoContent: Bool {
        photoDrafts.isEmpty && fieldDrafts.allSatisfy { draft in
            guard draft.fieldDefinition.displayRole == .none else { return true }
            switch draft.fieldType {
            case .text, .optionList:
                return draft.textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .number:
                return draft.numberValue == nil
            case .date:
                return draft.dateValue == nil
            case .boolean:
                return true
            }
        }
    }

    init(catalogue: Catalogue, item: CatalogueItem? = nil, duplicateSource: CatalogueItem? = nil, defaultStatusTab: StatusTab? = nil) {
        self.catalogue = catalogue
        self.existingItem = item
        self.duplicateSource = duplicateSource
        self.defaultStatusTab = defaultStatusTab
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    PhotoPickerView(photos: $photoDrafts, previewPhotoID: $previewPhotoID)

                    Section("Details") {
                        ForEach(fieldDrafts.indices, id: \.self) { index in
                            FieldInputView(label: sortedDefs[index].name, draft: $fieldDrafts[index])
                        }
                    }

                    Section("Notes") {
                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .lineLimit(4...8)
                            .focused($isNotesFocused)
                            .id(notesFieldID)
                            // Form keyboard avoidance only reveals the line that had focus, so lines added by typing
                            // or pasting would sit under the keyboard. Re-anchor on every height change.
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                geometry.size.height
                            } action: { _ in
                                guard isNotesFocused else { return }
                                revealNotesField(proxy, after: .milliseconds(50))
                            }
                    }
                }
                .onChange(of: isNotesFocused) { _, focused in
                    // Wait for the keyboard to finish rising, so the scroll targets the space above it.
                    guard focused else { return }
                    revealNotesField(proxy, after: .milliseconds(350))
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add", systemImage: "checkmark") {
                        Task { await saveItem() }
                    }
                    .disabled(hasNoContent || isSaving)
                }
            }
            // A swipe-down or tap outside would silently drop edits.
            .interactiveDismissDisabled(hasChanges)
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                loadItemData()
                loadedPhotoDrafts = photoDrafts
                loadedFieldDrafts = fieldDrafts
                loadedNotes = notes
                if isEditing {
                    baseline = EditBaseline(fieldDrafts: fieldDrafts, photoDrafts: photoDrafts, notes: notes)
                }
            }
            .alert("Couldn't Save Item", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError?.localizedDescription ?? "")
            }
            .sheet(isPresented: Binding(
                get: { previewPhotoID != nil },
                set: { if !$0 { previewPhotoID = nil } }
            )) {
                if let id = previewPhotoID {
                    PhotoEditDetailSheet(
                        draft: bindingFor(id),
                        totalCount: photoDrafts.count,
                        position: (photoDrafts.firstIndex(where: { $0.id == id }) ?? 0) + 1,
                        onDelete: {
                            withAnimation {
                                photoDrafts.removeAll { $0.id == id }
                                for index in photoDrafts.indices { photoDrafts[index].priority = index }
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func revealNotesField(_ proxy: ScrollViewProxy, after delay: Duration) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard isNotesFocused else { return }
            withAnimation {
                proxy.scrollTo(notesFieldID, anchor: .bottom)
            }
        }
    }

    private func bindingFor(_ id: UUID) -> Binding<PhotoDraft> {
        Binding(
            get: { photoDrafts.first(where: { $0.id == id }) ?? PhotoDraft(imageData: Data(), priority: 0) },
            set: { newDraft in
                if let index = photoDrafts.firstIndex(where: { $0.id == id }) {
                    photoDrafts[index] = newDraft
                }
            }
        )
    }

    // MARK: - Load

    private func loadItemData() {
        sortedDefs = catalogue.sortedFieldDefinitions

        if let item = existingItem {
            fieldDrafts = sortedDefs.map { def in
                var draft = FieldValueDraft(
                    fieldDefinition: def,
                    fieldType: def.fieldType
                )
                if let fv = item.value(for: def) {
                    switch def.fieldType {
                    case .text, .optionList:
                        draft.textValue = fv.textValue ?? ""
                    case .number:
                        draft.numberValue = fv.numberValue
                    case .date:
                        draft.dateValue = fv.dateValue
                    case .boolean:
                        draft.boolValue = fv.boolValue ?? false
                    }
                }
                return draft
            }

            photoDrafts = item.photos
                .sorted { $0.priority < $1.priority }
                .enumerated()
                .map { index, photo in
                    PhotoDraft(
                        imageData: photo.imageData,
                        caption: photo.caption ?? "",
                        priority: index,
                        existingPhotoID: photo.persistentModelID
                    )
                }

            notes = item.notes ?? ""
        } else if let source = duplicateSource {
            // Duplicate: saves as a new item.
            fieldDrafts = sortedDefs.map { def in
                var draft = FieldValueDraft(fieldDefinition: def, fieldType: def.fieldType)
                if let fv = source.value(for: def) {
                    switch def.fieldType {
                    case .text, .optionList: draft.textValue = fv.textValue ?? ""
                    case .number:            draft.numberValue = fv.numberValue
                    case .date:              draft.dateValue = fv.dateValue
                    case .boolean:           draft.boolValue = fv.boolValue ?? false
                    }
                }
                return draft
            }
            photoDrafts = source.photos
                .sorted { $0.priority < $1.priority }
                .enumerated()
                .map { index, photo in
                    PhotoDraft(imageData: photo.imageData, caption: photo.caption ?? "", priority: index)
                }
            notes = source.notes ?? ""
        } else {
            fieldDrafts = sortedDefs.map { def in
                var draft = FieldValueDraft(fieldDefinition: def, fieldType: def.fieldType)
                switch def.fieldType {
                case .optionList:
                    if let opts = def.optionListOptions,
                       let defaultVal = opts.defaultValue,
                       opts.options.contains(defaultVal) {
                        draft.textValue = defaultVal
                    }
                case .boolean:
                    draft.boolValue = def.booleanOptions?.defaultValue ?? false
                case .text, .number, .date:
                    break
                }
                return draft
            }
            applyDefaultStatusTab()
        }
    }

    /// Adding while filtered to "Wishlist" makes a wishlist item.
    private func applyDefaultStatusTab() {
        guard let statusField = catalogue.statusField,
              let index = fieldDrafts.firstIndex(where: { $0.fieldID == statusField.fieldID })
        else { return }

        let effectiveTab: StatusTab? = {
            if let tab = defaultStatusTab, tab != .all { return tab }
            return catalogue.defaultStatusTabForNewItems
        }()

        switch effectiveTab {
        case .option(let value):
            guard statusField.fieldType == .optionList else { return }
            fieldDrafts[index].textValue = value
        case .boolTrue:
            guard statusField.fieldType == .boolean else { return }
            fieldDrafts[index].boolValue = true
        case .boolFalse:
            guard statusField.fieldType == .boolean else { return }
            fieldDrafts[index].boolValue = false
        case .all, nil:
            break
        }
    }

    // MARK: - Save

    /// Evicts the in-memory cover *before* saving: the save bumps `modifiedDate`, which the list's
    /// thumbnails reload on, and they mustn't find the old image still cached.
    private func saveItem() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let photosEdited = photoDrafts != loadedPhotoDrafts
        if let existingItem, photosEdited {
            await ImageCache.shared.removeImage(for: "cover_\(existingItem.persistentModelID)")
        }

        let outcome: ItemSaveService.Outcome
        do {
            outcome = try ItemSaveService.save(
                existing: existingItem,
                in: catalogue,
                notes: notes,
                fieldDrafts: fieldDrafts,
                photoDrafts: photoDrafts,
                baseline: baseline,
                context: modelContext
            )
        } catch {
            saveError = error
            return
        }

        // The cover lives in the file cache, not the model, to keep page fetches light. Written
        // after the save so a new item has its permanent identifier.
        if outcome.photosChanged {
            let itemID = outcome.item.persistentModelID
            if !photosEdited {
                // A photo removed on another device while the sheet was open: the eviction was skipped.
                await ImageCache.shared.removeImage(for: "cover_\(itemID)")
            }
            if let data = outcome.coverThumbnailData {
                ThumbnailLoader.writeThumbnailToCache(data, for: itemID)
            } else if let url = ThumbnailLoader.thumbnailCacheURL(for: itemID) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview("New Item") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let catalogue = Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF")
    container.mainContext.insert(catalogue)

    let field1 = FieldDefinition(name: "Manufacturer", fieldType: .text, priority: 0)
    field1.catalogue = catalogue
    container.mainContext.insert(field1)

    let field2 = FieldDefinition(name: "Year", fieldType: .number, priority: 1)
    field2.catalogue = catalogue
    container.mainContext.insert(field2)

    let field3 = FieldDefinition(name: "Assembled", fieldType: .boolean, priority: 2)
    field3.catalogue = catalogue
    container.mainContext.insert(field3)

    return AddEditItemView(catalogue: catalogue)
        .modelContainer(container)
}
