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
    /// Status the new item should start in — the tab the user was viewing when they tapped +.
    /// `nil` falls back to the status field's own configured default.
    let defaultStatusTab: StatusTab?

    // MARK: - Form State

    @State private var sortedDefs: [FieldDefinition] = []
    @State private var fieldDrafts: [FieldValueDraft] = []
    @State private var photoDrafts: [PhotoDraft] = []
    @State private var notes: String = ""
    @State private var previewPhotoID: UUID? = nil
    @State private var hasLoaded: Bool = false
    /// A failed save keeps the sheet open with the drafts intact rather than dismissing as
    /// if it had worked.
    @State private var saveError: Error?
    /// Guards the Save button against a second tap while the first save is in flight.
    @State private var isSaving = false
    /// The form as loaded, in every mode. The photos tell the save whether the thumbnail
    /// needs invalidating; all three tell `hasChanges` whether dismissing would lose an edit.
    /// Distinct from `baseline`, which must stay nil when duplicating so the save writes
    /// every pre-filled value to the new item.
    @State private var loadedPhotoDrafts: [PhotoDraft] = []
    @State private var loadedFieldDrafts: [FieldValueDraft] = []
    @State private var loadedNotes: String = ""
    /// Everything as loaded when editing, so the save writes only what the user changed
    /// and not a stale copy of what another device edited meanwhile — see `EditBaseline`.
    @State private var baseline: EditBaseline?
    @FocusState private var isNotesFocused: Bool

    /// Anchor for scrolling the notes row into view; see `revealNotesField`.
    private let notesFieldID = "notesField"

    // MARK: - Computed

    private var isEditing: Bool { existingItem != nil }

    /// Whether dismissing without saving would lose something: anything that differs from
    /// what the sheet opened with. A duplicate's pre-filled values and a new item's default
    /// status are what it opened with, so they don't count until the user touches them.
    private var hasChanges: Bool {
        guard hasLoaded else { return false }
        return notes != loadedNotes
            || photoDrafts != loadedPhotoDrafts
            || fieldDrafts.count != loadedFieldDrafts.count
            || !zip(fieldDrafts, loadedFieldDrafts).allSatisfy { $0.hasSameValue(as: $1) }
    }

    // Boolean fields always have a value (true/false), so they don't count toward "has content" —
    // otherwise every item would trivially pass validation regardless of user input.
    // Status and flag fields are excluded for the same reason: a status field pre-filled with
    // its default value would otherwise make a completely empty item look like it has content.
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
                            // The form's own keyboard avoidance only reveals the line that
                            // had focus when the keyboard came up. When the field grows —
                            // typing past a line, or pasting a paragraph — the new lines
                            // extend below it, under the keyboard, and nothing follows them.
                            // Re-anchoring on every height change keeps the whole box in view.
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                geometry.size.height
                            } action: { _ in
                                guard isNotesFocused else { return }
                                revealNotesField(proxy, after: .milliseconds(50))
                            }
                    }
                }
                .onChange(of: isNotesFocused) { _, focused in
                    // Wait for the keyboard to finish rising, so the scroll targets the
                    // space above it rather than the full height it had before.
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        Task { await saveItem() }
                    }
                    .disabled(hasNoContent || isSaving)
                }
            }
            // A swipe-down, or a tap outside the sheet on iPad, would silently drop the
            // edits; once there are any, dismissal has to go through Cancel.
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

    /// Scrolls so the entire notes box sits just above the keyboard, not merely the cursor line.
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
                        priority: index,
                        existingPhotoID: photo.persistentModelID
                    )
                }

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
            notes = source.notes ?? ""
        } else {
            // Create mode: blank drafts, pre-populate per-type defaults
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

    /// Seeds the status field's draft from the tab the user was viewing, so adding an item
    /// while filtered to "Wishlist" produces a wishlist item. Falls back to the status
    /// field's own configured default when no tab context was passed (or "All" was active).
    private func applyDefaultStatusTab() {
        guard let statusField = catalogue.statusField,
              let index = fieldDrafts.firstIndex(where: { $0.fieldID == statusField.fieldID })
        else { return }

        // `.all` carries no status, so defer to the field's configured default.
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

    /// Diffs the drafts against the stored item (see `ItemSaveService`) and keeps the cover
    /// thumbnail caches in step. The in-memory cache is evicted *before* the save: the save
    /// bumps `modifiedDate`, which is what the list's thumbnail views reload on, and they
    /// must not find the old image still cached when they do.
    private func saveItem() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        // Only a photo change can make the cached cover wrong; a fields-only edit keeps it.
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

        // The cover thumbnail lives in the filesystem cache, not the model: storing it on
        // CatalogueItem bloats the SQLite rows the main context reads on every page fetch.
        // Written after the save so a new item has its permanent identifier.
        if outcome.photosChanged {
            let itemID = outcome.item.persistentModelID
            if !photosEdited {
                // The store disagreed with the drafts (a photo removed on another device
                // while the sheet was open), so the eviction above was skipped.
                await ImageCache.shared.removeImage(for: "cover_\(itemID)")
            }
            if let data = outcome.coverThumbnailData {
                ThumbnailLoader.writeThumbnailToCache(data, for: itemID)
            } else if let url = ThumbnailLoader.thumbnailCacheURL(for: itemID) {
                // All photos removed — drop the stale disk thumbnail so tier-2 doesn't serve it.
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
