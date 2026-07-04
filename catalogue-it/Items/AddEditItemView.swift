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
    let defaultIsWishlist: Bool

    // MARK: - Form State

    @State private var sortedDefs: [FieldDefinition] = []
    @State private var fieldDrafts: [FieldValueDraft] = []
    @State private var photoDrafts: [PhotoDraft] = []
    @State private var isWishlist: Bool = false
    @State private var notes: String = ""
    @State private var previewPhotoID: UUID? = nil
    @State private var hasLoaded: Bool = false

    // MARK: - Computed

    private var isEditing: Bool { existingItem != nil }

    init(catalogue: Catalogue, item: CatalogueItem? = nil, duplicateSource: CatalogueItem? = nil, defaultIsWishlist: Bool = false) {
        self.catalogue = catalogue
        self.existingItem = item
        self.duplicateSource = duplicateSource
        self.defaultIsWishlist = defaultIsWishlist
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                PhotoPickerView(photos: $photoDrafts, previewPhotoID: $previewPhotoID)

                Section("Details") {
                    ForEach(fieldDrafts.indices, id: \.self) { index in
                        FieldInputView(label: sortedDefs[index].name, draft: $fieldDrafts[index])
                    }
                }

                Section("Item Info") {
                    Toggle("Add to Wishlist", isOn: $isWishlist)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveItem()
                    }
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                loadItemData()
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
        sortedDefs = catalogue.fieldDefinitions.sorted { $0.priority < $1.priority }

        if let item = existingItem {
            // Edit mode: populate from existing item
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
                        priority: index
                    )
                }

            isWishlist = item.isWishlist
            notes = item.notes ?? ""
        } else if let source = duplicateSource {
            // Clone mode: populate from source item, saves as a new item
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
            isWishlist = source.isWishlist
            notes = source.notes ?? ""
        } else {
            // Create mode: blank drafts, pre-populate option list defaults
            fieldDrafts = sortedDefs.map { def in
                var draft = FieldValueDraft(fieldDefinition: def, fieldType: def.fieldType)
                if def.fieldType == .optionList,
                   let opts = def.optionListOptions,
                   let defaultVal = opts.defaultValue,
                   opts.options.contains(defaultVal) {
                    draft.textValue = defaultVal
                }
                return draft
            }
            isWishlist = defaultIsWishlist
        }
    }

    // MARK: - Save

    private func saveItem() {
        let targetItem: CatalogueItem

        if let existing = existingItem {
            // Edit path
            existing.isWishlist = isWishlist
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

            for fv in existing.fieldValues { modelContext.delete(fv) }
            for photo in existing.photos { modelContext.delete(photo) }

            targetItem = existing
        } else {
            // Create path
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let newItem = CatalogueItem(
                isWishlist: isWishlist,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            newItem.catalogue = catalogue
            modelContext.insert(newItem)
            targetItem = newItem
        }

        // Field values
        var createdFieldValues: [FieldValue] = []
        for draft in fieldDrafts {
            let fv = FieldValue(fieldDefinition: draft.fieldDefinition, fieldType: draft.fieldType)
            switch draft.fieldType {
            case .text, .optionList:
                let trimmedText = draft.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
                fv.textValue = trimmedText.isEmpty ? nil : trimmedText
            case .number:
                fv.numberValue = draft.numberValue
            case .date:
                fv.dateValue = draft.dateValue
            case .boolean:
                fv.boolValue = draft.boolValue
            }
            fv.sortKey = SortKeyEncoder.sortKey(for: fv)
            fv.item = targetItem
            modelContext.insert(fv)
            createdFieldValues.append(fv)
        }

        // Denormalised search blob — kept in sync so SQLite can filter without loading children.
        targetItem.searchText = SearchTextBuilder.build(from: createdFieldValues)

        // Photos
        for draft in photoDrafts {
            let trimmedCaption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let photo = ItemPhoto(
                imageData: draft.imageData,
                thumbnailData: draft.imageData.makeThumbnail(),
                priority: draft.priority,
                caption: trimmedCaption.isEmpty ? nil : trimmedCaption
            )
            photo.item = targetItem
            modelContext.insert(photo)
        }

        // Compute cover thumbnail before saving so it's ready to write to the
        // filesystem cache immediately after save (when the permanent ID is available).
        let coverThumbnailData = photoDrafts
            .sorted(by: { $0.priority < $1.priority })
            .first
            .flatMap { $0.imageData.makeThumbnail() }

        // Save immediately so newly inserted models get permanent PersistentIdentifiers
        // before any view renders them. Without this, autosave fires 20+ seconds later:
        // ItemPaginationController never sees NSManagedObjectContextDidSave, so the
        // new item doesn't appear; and if temporary IDs are handed to views before the
        // save converts them, accessing the model via a stale temporary ID crashes.
        try? modelContext.save()

        // Write the cover thumbnail to the filesystem cache (not the model).
        // Storing thumbnails in the model bloats CatalogueItem SQLite rows — the main
        // context reads those bytes on every page fetch even though it never uses them.
        // The filesystem cache persists across launches and is regenerable from source photos.
        let itemID = targetItem.persistentModelID
        if let data = coverThumbnailData {
            ThumbnailLoader.writeThumbnailToCache(data, for: itemID)
        } else {
            // All photos removed — delete the stale disk thumbnail so tier-2 doesn't serve it.
            if let url = ThumbnailLoader.thumbnailCacheURL(for: itemID) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Invalidate the in-memory decoded-image cache so the updated thumbnail is shown.
        Task { @MainActor in
            await ImageCache.shared.removeImage(for: "cover_\(itemID)")
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview("New Item") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
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
