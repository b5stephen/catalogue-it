//
//  ItemSaveServiceTests.swift
//  UnitTests
//

import Testing
import Foundation
import CoreGraphics
import ImageIO
import SwiftData
@testable import catalogue_it

// MARK: - Item Save Service Tests

/// Covers the diff-and-update save that replaced "delete every FieldValue and ItemPhoto and
/// recreate them". The property that matters for iCloud is *record identity*: an edit must
/// leave untouched records untouched, so CloudKit merges properties rather than replaying
/// deletions. Nearly every test therefore asserts on `persistentModelID` before and after.
@MainActor
struct ItemSaveServiceTests {

    // MARK: - Fixtures

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let catalogue: Catalogue
        let title: FieldDefinition
        let year: FieldDefinition
        let status: FieldDefinition
        let favourite: FieldDefinition

        var sortedDefs: [FieldDefinition] { catalogue.sortedFieldDefinitions }
    }

    /// A catalogue with a text field, a number field, an option-list status field and a
    /// boolean flag field — one of each shape the diff has to compare.
    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext

        let catalogue = Catalogue(name: "Films")
        context.insert(catalogue)

        let title = FieldDefinition(name: "Title", fieldType: .text, priority: 0)
        title.catalogue = catalogue
        context.insert(title)

        let year = FieldDefinition(name: "Year", fieldType: .number, priority: 1)
        year.catalogue = catalogue
        context.insert(year)

        let status = FieldDefinition(name: "Status", fieldType: .optionList, priority: 2, displayRole: .statusTabs)
        status.fieldOptions = .optionList(OptionListOptions(options: ["Owned", "Wishlist"], defaultValue: "Owned"))
        status.catalogue = catalogue
        context.insert(status)

        let favourite = FieldDefinition(name: "Favourite", fieldType: .boolean, priority: 3, displayRole: .flagFilter)
        favourite.catalogue = catalogue
        context.insert(favourite)

        try context.save()
        return Fixture(container: container, context: context, catalogue: catalogue,
                       title: title, year: year, status: status, favourite: favourite)
    }

    /// Drafts for every definition, in priority order, with the given values.
    private func drafts(
        for fixture: Fixture,
        title: String = "Alien",
        year: Double? = 1979,
        status: String = "Owned",
        favourite: Bool = false
    ) -> [FieldValueDraft] {
        fixture.sortedDefs.map { def in
            var draft = FieldValueDraft(fieldDefinition: def, fieldType: def.fieldType)
            switch def.fieldID {
            case fixture.title.fieldID: draft.textValue = title
            case fixture.year.fieldID: draft.numberValue = year
            case fixture.status.fieldID: draft.textValue = status
            case fixture.favourite.fieldID: draft.boolValue = favourite
            default: break
            }
            return draft
        }
    }

    /// Drafts rebuilt from a stored item, the way `AddEditItemView.loadItemData` does it.
    private func photoDrafts(from item: CatalogueItem) -> [PhotoDraft] {
        item.photos
            .sorted { $0.priority < $1.priority }
            .enumerated()
            .map { index, photo in
                PhotoDraft(imageData: photo.imageData, caption: photo.caption ?? "", priority: index,
                           existingPhotoID: photo.persistentModelID)
            }
    }

    /// Solid-colour PNG data. A real image, so `makeThumbnail()` produces bytes.
    private func makePNGData(width: Int = 8, height: Int = 8, red: CGFloat = 0.8) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = try #require(CFDataCreateMutable(kCFAllocatorDefault, 0))
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @discardableResult
    private func create(
        in fixture: Fixture,
        notes: String = "",
        fieldDrafts: [FieldValueDraft]? = nil,
        photoDrafts: [PhotoDraft] = [],
        now: Date = .now
    ) throws -> CatalogueItem {
        try ItemSaveService.save(
            existing: nil, in: fixture.catalogue, notes: notes,
            fieldDrafts: fieldDrafts ?? drafts(for: fixture),
            photoDrafts: photoDrafts, context: fixture.context, now: now
        ).item
    }

    private func update(
        _ item: CatalogueItem,
        in fixture: Fixture,
        notes: String? = nil,
        fieldDrafts: [FieldValueDraft]? = nil,
        photoDrafts: [PhotoDraft]? = nil,
        baseline: EditBaseline? = nil,
        now: Date = .now
    ) throws -> ItemSaveService.Outcome {
        try ItemSaveService.save(
            existing: item, in: fixture.catalogue,
            notes: notes ?? item.notes ?? "",
            fieldDrafts: fieldDrafts ?? drafts(for: fixture),
            photoDrafts: photoDrafts ?? self.photoDrafts(from: item),
            baseline: baseline,
            context: fixture.context, now: now
        )
    }

    /// What `AddEditItemView` captures when the sheet opens on `item`.
    private func baseline(for item: CatalogueItem, in fixture: Fixture) -> EditBaseline {
        let fieldDrafts = fixture.sortedDefs.map { def in
            var draft = FieldValueDraft(fieldDefinition: def, fieldType: def.fieldType)
            if let fv = value(def, on: item) {
                switch def.fieldType {
                case .text, .optionList: draft.textValue = fv.textValue ?? ""
                case .number: draft.numberValue = fv.numberValue
                case .date: draft.dateValue = fv.dateValue
                case .boolean: draft.boolValue = fv.boolValue ?? false
                }
            }
            return draft
        }
        return EditBaseline(fieldDrafts: fieldDrafts, photoDrafts: photoDrafts(from: item), notes: item.notes ?? "")
    }

    /// Simulates another device's edit landing while a sheet is open: a direct write to
    /// the store, bypassing the drafts.
    private func remoteEdit(_ edit: () -> Void, in fixture: Fixture) throws {
        edit()
        try fixture.context.save()
    }

    private func value(_ def: FieldDefinition, on item: CatalogueItem) -> FieldValue? {
        item.fieldValues.first { $0.fieldDefinition?.fieldID == def.fieldID }
    }

    private func ids(of values: [FieldValue]) -> Set<PersistentIdentifier> {
        Set(values.map(\.persistentModelID))
    }

    // MARK: - Create

    @Test func createWritesEveryFieldValueAndDerivedColumns() throws {
        let f = try makeFixture()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)

        let item = try create(in: f, notes: "  boxed  ", fieldDrafts: drafts(for: f, favourite: true), now: stamp)

        #expect(item.catalogue === f.catalogue)
        #expect(item.notes == "boxed")
        #expect(item.fieldValues.count == 4)
        #expect(value(f.title, on: item)?.textValue == "Alien")
        #expect(value(f.year, on: item)?.numberValue == 1979)
        #expect(value(f.status, on: item)?.textValue == "Owned")
        #expect(value(f.favourite, on: item)?.boolValue == true)
        #expect(item.searchText.contains("alien"))
        #expect(item.statusValue == "Owned")
        #expect(item.flagKeys == ItemFacetBuilder.flagToken(for: f.favourite.fieldID))
        #expect(item.modifiedDate == stamp)
        #expect(!f.context.hasChanges, "save() must have been called")
    }

    @Test func createComputesSortAndTiebreakKeys() throws {
        let f = try makeFixture()
        let item = try create(in: f)

        for fv in item.fieldValues {
            #expect(fv.sortKey == SortKeyEncoder.sortKey(for: fv))
            #expect(fv.tiebreakKey != SortKeyEncoder.missingValueSentinel)
        }
    }

    @Test func createInsertsPhotosInDraftOrder() throws {
        let f = try makeFixture()
        let first = try makePNGData(red: 0.1)
        let second = try makePNGData(red: 0.9)

        let outcome = try ItemSaveService.save(
            existing: nil, in: f.catalogue, notes: "", fieldDrafts: drafts(for: f),
            photoDrafts: [
                PhotoDraft(imageData: second, caption: " back ", priority: 1),
                PhotoDraft(imageData: first, priority: 0),
            ],
            context: f.context
        )

        let photos = outcome.item.photos.sorted { $0.priority < $1.priority }
        #expect(photos.count == 2)
        #expect(photos[0].imageData == first)
        #expect(photos[0].caption == nil)
        #expect(photos[1].imageData == second)
        #expect(photos[1].caption == "back")
        #expect(photos.allSatisfy { $0.thumbnailData != nil })
        #expect(outcome.photosChanged)
        #expect(outcome.coverThumbnailData == first.makeThumbnail())
    }

    // MARK: - Field value identity

    @Test func editingOneFieldUpdatesThatRecordInPlaceAndLeavesTheRestUntouched() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        let before = ids(of: item.fieldValues)
        let yearID = try #require(value(f.year, on: item)).persistentModelID

        let outcome = try update(item, in: f, fieldDrafts: drafts(for: f, year: 1986))

        #expect(ids(of: item.fieldValues) == before, "no FieldValue was deleted or recreated")
        #expect(value(f.year, on: item)?.persistentModelID == yearID)
        #expect(value(f.year, on: item)?.numberValue == 1986)
        #expect(value(f.title, on: item)?.textValue == "Alien")
        #expect(outcome.fieldsChanged)
        #expect(!outcome.photosChanged)
        #expect(!outcome.notesChanged)
    }

    @Test func clearingATextFieldStoresNilNotEmptyString() throws {
        let f = try makeFixture()
        let item = try create(in: f)

        _ = try update(item, in: f, fieldDrafts: drafts(for: f, title: "   "))

        #expect(value(f.title, on: item)?.textValue == nil)
        #expect(value(f.title, on: item)?.sortKey == SortKeyEncoder.missingValueSentinel)
    }

    @Test func editingOneFieldRefreshesDerivedColumns() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        let oldTitleTiebreak = try #require(value(f.title, on: item)).tiebreakKey

        _ = try update(item, in: f, fieldDrafts: drafts(for: f, year: 1986, status: "Wishlist", favourite: true))

        #expect(item.statusValue == "Wishlist")
        #expect(item.flagKeys == ItemFacetBuilder.flagToken(for: f.favourite.fieldID))
        #expect(item.searchText.contains("wishlist"))
        #expect(item.searchText.contains("alien"))
        // The year sits in the title's tiebreak key, so it must have been rewritten.
        #expect(value(f.title, on: item)?.tiebreakKey != oldTitleTiebreak)
    }

    @Test func fieldAddedToCatalogueAfterCreationGetsAValueInsertedOnlyForItself() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        let before = ids(of: item.fieldValues)

        let director = FieldDefinition(name: "Director", fieldType: .text, priority: 4)
        f.context.insert(director)
        director.catalogue = f.catalogue
        try f.context.save()

        // `drafts(for:)` now covers the new field too, with an empty value; fill it in.
        var newDrafts = drafts(for: f)
        let directorIndex = try #require(newDrafts.firstIndex { $0.fieldDefinition.fieldID == director.fieldID })
        newDrafts[directorIndex].textValue = "Ridley Scott"
        let outcome = try update(item, in: f, fieldDrafts: newDrafts)

        #expect(item.fieldValues.count == 5)
        #expect(before.isSubset(of: ids(of: item.fieldValues)))
        #expect(value(director, on: item)?.textValue == "Ridley Scott")
        #expect(outcome.fieldsChanged)
    }

    @Test func twoDraftsForOneDefinitionProduceOneValue() throws {
        let f = try makeFixture()
        let item = try create(in: f)

        var newDrafts = drafts(for: f, title: "First")
        var second = FieldValueDraft(fieldDefinition: f.title, fieldType: .text)
        second.textValue = "Second"
        newDrafts.append(second)
        _ = try update(item, in: f, fieldDrafts: newDrafts)

        #expect(item.fieldValues.filter { $0.fieldDefinition?.fieldID == f.title.fieldID }.count == 1)
        #expect(value(f.title, on: item)?.textValue == "Second", "later draft wins, in place")
    }

    @Test func duplicateValuesForOneDefinitionCollapseToOne() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        // The sort of thing a merge can leave behind: two records for the same field.
        let stray = FieldValue(fieldDefinition: nil, fieldType: .text)
        f.context.insert(stray)
        stray.fieldDefinition = f.title
        stray.item = item
        try f.context.save()
        #expect(item.fieldValues.count == 5)

        _ = try update(item, in: f)

        #expect(item.fieldValues.count == 4)
        #expect(item.fieldValues.filter { $0.fieldDefinition?.fieldID == f.title.fieldID }.count == 1)
        #expect(value(f.title, on: item)?.textValue == "Alien")
    }

    @Test func orphanedValueWithNoDefinitionIsLeftAlone() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        // A value whose definition hasn't synced yet looks exactly like this. Deleting it
        // would destroy data the user entered on another device.
        let orphan = FieldValue(fieldDefinition: nil, fieldType: .text)
        orphan.textValue = "not yet linked"
        f.context.insert(orphan)
        orphan.item = item
        try f.context.save()
        let orphanID = orphan.persistentModelID

        let outcome = try update(item, in: f)

        #expect(item.fieldValues.contains { $0.persistentModelID == orphanID })
        #expect(!outcome.fieldsChanged)
    }

    @Test func definitionTypeChangeResetsTheValueUnderTheNewType() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        let yearID = try #require(value(f.year, on: item)).persistentModelID

        f.year.fieldType = .text
        try f.context.save()
        var newDrafts = drafts(for: f, year: nil)
        let yearIndex = try #require(newDrafts.firstIndex { $0.fieldDefinition.fieldID == f.year.fieldID })
        newDrafts[yearIndex] = FieldValueDraft(fieldDefinition: f.year, fieldType: .text)
        newDrafts[yearIndex].textValue = "late seventies"

        let outcome = try update(item, in: f, fieldDrafts: newDrafts)

        let yearValue = try #require(value(f.year, on: item))
        #expect(yearValue.persistentModelID == yearID, "retyped in place, not recreated")
        #expect(yearValue.fieldType == .text)
        #expect(yearValue.textValue == "late seventies")
        #expect(yearValue.numberValue == nil)
        #expect(outcome.fieldsChanged)
    }

    // MARK: - Photos

    @Test func addingAPhotoLeavesEveryFieldValueAndExistingPhotoUntouched() throws {
        let f = try makeFixture()
        let original = try makePNGData(red: 0.1)
        let item = try create(in: f, photoDrafts: [PhotoDraft(imageData: original, caption: "front", priority: 0)])
        let fieldIDs = ids(of: item.fieldValues)
        let originalPhotoID = try #require(item.photos.first).persistentModelID
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)

        // This is the report from the field: add one photo, nothing else.
        let added = try makePNGData(red: 0.9)
        var newDrafts = photoDrafts(from: item)
        newDrafts.append(PhotoDraft(imageData: added, priority: 1))
        let outcome = try update(item, in: f, photoDrafts: newDrafts, now: stamp)

        #expect(ids(of: item.fieldValues) == fieldIDs, "field values must survive a photo-only edit")
        #expect(value(f.title, on: item)?.textValue == "Alien")
        #expect(value(f.year, on: item)?.numberValue == 1979)
        let photos = item.photos.sorted { $0.priority < $1.priority }
        #expect(photos.count == 2)
        #expect(photos[0].persistentModelID == originalPhotoID, "existing photo keeps its record")
        #expect(photos[0].caption == "front")
        #expect(photos[1].imageData == added)
        #expect(outcome.photosChanged)
        #expect(!outcome.fieldsChanged)
        #expect(outcome.coverThumbnailData == original.makeThumbnail(), "cover is still the first photo")
        #expect(item.modifiedDate == stamp)
    }

    @Test func removingAPhotoDeletesOnlyThatRecord() throws {
        let f = try makeFixture()
        let keep = try makePNGData(red: 0.1)
        let drop = try makePNGData(red: 0.9)
        let item = try create(in: f, photoDrafts: [
            PhotoDraft(imageData: keep, priority: 0),
            PhotoDraft(imageData: drop, priority: 1),
        ])
        let keepID = try #require(item.photos.first { $0.imageData == keep }).persistentModelID

        let remaining = photoDrafts(from: item).filter { $0.imageData == keep }
        let outcome = try update(item, in: f, photoDrafts: remaining)

        #expect(item.photos.count == 1)
        #expect(item.photos.first?.persistentModelID == keepID)
        #expect(outcome.photosChanged)
        #expect(try f.context.fetchCount(FetchDescriptor<ItemPhoto>()) == 1, "the removed photo is gone from the store")
    }

    @Test func removingTheLastPhotoReportsNoCover() throws {
        let f = try makeFixture()
        let item = try create(in: f, photoDrafts: [PhotoDraft(imageData: try makePNGData(), priority: 0)])

        let outcome = try update(item, in: f, photoDrafts: [])

        #expect(item.photos.isEmpty)
        #expect(outcome.photosChanged)
        #expect(outcome.coverThumbnailData == nil)
    }

    @Test func reorderingPhotosRewritesPrioritiesInPlace() throws {
        let f = try makeFixture()
        let a = try makePNGData(red: 0.1)
        let b = try makePNGData(red: 0.9)
        let item = try create(in: f, photoDrafts: [
            PhotoDraft(imageData: a, priority: 0),
            PhotoDraft(imageData: b, priority: 1),
        ])
        let before = Set(item.photos.map(\.persistentModelID))

        var reordered = photoDrafts(from: item)
        reordered.swapAt(0, 1)
        for index in reordered.indices { reordered[index].priority = index }
        let outcome = try update(item, in: f, photoDrafts: reordered)

        #expect(Set(item.photos.map(\.persistentModelID)) == before)
        let photos = item.photos.sorted { $0.priority < $1.priority }
        #expect(photos[0].imageData == b)
        #expect(photos[1].imageData == a)
        #expect(outcome.photosChanged)
        #expect(outcome.coverThumbnailData == b.makeThumbnail(), "the cover follows the new first photo")
    }

    @Test func editingACaptionDoesNotTouchTheImage() throws {
        let f = try makeFixture()
        let item = try create(in: f, photoDrafts: [PhotoDraft(imageData: try makePNGData(), priority: 0)])
        let photo = try #require(item.photos.first)
        let photoID = photo.persistentModelID
        let thumbnail = photo.thumbnailData

        var edited = photoDrafts(from: item)
        edited[0].caption = " Box art "
        let outcome = try update(item, in: f, photoDrafts: edited)

        #expect(item.photos.first?.persistentModelID == photoID)
        #expect(item.photos.first?.caption == "Box art")
        #expect(item.photos.first?.thumbnailData == thumbnail)
        #expect(outcome.photosChanged)
    }

    @Test func draftWhosePhotoVanishedIsInsertedAfresh() throws {
        let f = try makeFixture()
        let bytes = try makePNGData()
        let item = try create(in: f, photoDrafts: [PhotoDraft(imageData: bytes, priority: 0)])
        let drafts = photoDrafts(from: item)

        // Another device deleted the photo while the sheet was open.
        f.context.delete(try #require(item.photos.first))
        try f.context.save()
        #expect(item.photos.isEmpty)

        let outcome = try update(item, in: f, photoDrafts: drafts)

        #expect(item.photos.count == 1)
        #expect(item.photos.first?.imageData == bytes)
        #expect(outcome.photosChanged)
    }

    @Test func duplicatedItemPhotosBecomeNewRecordsOnTheNewItem() throws {
        let f = try makeFixture()
        let bytes = try makePNGData()
        let source = try create(in: f, photoDrafts: [PhotoDraft(imageData: bytes, priority: 0)])
        let sourcePhotoID = try #require(source.photos.first).persistentModelID

        // Duplicate mode builds drafts without `existingPhotoID`, so the copy must not steal
        // the source's photo record.
        let copy = try create(in: f, photoDrafts: [PhotoDraft(imageData: bytes, priority: 0)])

        #expect(source.photos.count == 1)
        #expect(source.photos.first?.persistentModelID == sourcePhotoID)
        #expect(copy.photos.count == 1)
        #expect(copy.photos.first?.persistentModelID != sourcePhotoID)
    }

    // MARK: - Notes and modifiedDate

    @Test func notesOnlyEditBumpsModifiedDateAndNothingElse() throws {
        let f = try makeFixture()
        let item = try create(in: f, now: Date(timeIntervalSince1970: 1_700_000_000))
        let fieldIDs = ids(of: item.fieldValues)
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)

        let outcome = try update(item, in: f, notes: "  arrived damaged ", now: stamp)

        #expect(item.notes == "arrived damaged")
        #expect(outcome.notesChanged)
        #expect(!outcome.fieldsChanged)
        #expect(!outcome.photosChanged)
        #expect(ids(of: item.fieldValues) == fieldIDs)
        #expect(item.modifiedDate == stamp)
    }

    @Test func saveWithNothingChangedIsANoOp() throws {
        let f = try makeFixture()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let item = try create(in: f, notes: "kept", photoDrafts: [PhotoDraft(imageData: try makePNGData(), priority: 0)], now: created)
        let fieldIDs = ids(of: item.fieldValues)
        let photoIDs = Set(item.photos.map(\.persistentModelID))

        let outcome = try update(item, in: f, now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(!outcome.didChange)
        #expect(outcome.coverThumbnailData == nil, "no thumbnail work when photos are untouched")
        #expect(item.modifiedDate == created, "an untouched item must not look edited to other devices")
        #expect(ids(of: item.fieldValues) == fieldIDs)
        #expect(Set(item.photos.map(\.persistentModelID)) == photoIDs)
        #expect(!f.context.hasChanges)
    }

    @Test func derivedColumnUpkeepDoesNotBumpModifiedDate() throws {
        let f = try makeFixture()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let item = try create(in: f, now: created)
        // A backfill or an older build could leave a stale key behind; repairing it is not
        // a user edit.
        try #require(value(f.title, on: item)).sortKey = "stale"
        try f.context.save()

        let outcome = try update(item, in: f, now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(value(f.title, on: item)?.sortKey == SortKeyEncoder.sortKey(for: try #require(value(f.title, on: item))))
        #expect(!outcome.didChange)
        #expect(item.modifiedDate == created)
    }

    @Test func updateNotesSavesOnlyWhenTheTextActuallyChanged() throws {
        let f = try makeFixture()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let item = try create(in: f, notes: "same", now: created)
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(try ItemSaveService.updateNotes(" same ", on: item, context: f.context, now: stamp) == false)
        #expect(item.modifiedDate == created)

        #expect(try ItemSaveService.updateNotes("different", on: item, context: f.context, now: stamp) == true)
        #expect(item.notes == "different")
        #expect(item.modifiedDate == stamp)
        #expect(!f.context.hasChanges)

        #expect(try ItemSaveService.updateNotes("   ", on: item, context: f.context) == true)
        #expect(item.notes == nil)
    }

    @Test func newItemModifiedDateMatchesCreatedDate() throws {
        let item = CatalogueItem()
        #expect(item.modifiedDate == item.createdDate)
    }

    @Test func createdItemHasModifiedDateEqualToCreatedDate() throws {
        let f = try makeFixture()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)

        let item = try create(in: f, now: stamp)

        #expect(item.createdDate == stamp)
        #expect(item.modifiedDate == item.createdDate, "a never-edited item must not read as edited after creation")
    }

    @Test func fieldsOnlyEditLeavesPhotosUntouched() throws {
        let f = try makeFixture()
        let bytes = try makePNGData()
        let item = try create(in: f, photoDrafts: [PhotoDraft(imageData: bytes, caption: "front", priority: 0)])
        let photo = try #require(item.photos.first)
        let photoID = photo.persistentModelID
        let thumbnail = photo.thumbnailData

        let outcome = try update(item, in: f, fieldDrafts: drafts(for: f, title: "Aliens"))

        #expect(outcome.fieldsChanged)
        #expect(!outcome.photosChanged, "a text edit must not touch photo records (or re-upload their assets)")
        #expect(outcome.coverThumbnailData == nil)
        #expect(item.photos.count == 1)
        #expect(item.photos.first?.persistentModelID == photoID)
        #expect(item.photos.first?.imageData == bytes)
        #expect(item.photos.first?.thumbnailData == thumbnail)
        #expect(item.photos.first?.caption == "front")
    }

    // MARK: - Thumbnail key

    @Test func thumbnailKeyChangesWhenPhotosChangeAndNotOtherwise() throws {
        let f = try makeFixture()
        let item = try create(in: f, now: Date(timeIntervalSince1970: 1_700_000_000))
        let before = ThumbnailKey(item: item)

        _ = try update(item, in: f, now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(ThumbnailKey(item: item) == before, "a no-op save must not reload every visible thumbnail")

        var withPhoto = photoDrafts(from: item)
        withPhoto.append(PhotoDraft(imageData: try makePNGData(), priority: 0))
        _ = try update(item, in: f, photoDrafts: withPhoto, now: Date(timeIntervalSince1970: 1_900_000_000))
        #expect(ThumbnailKey(item: item) != before, "adding a photo must re-key the load")
    }

    @Test func thumbnailKeyChangesWhenTheCacheGenerationIsBumped() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        let before = ThumbnailKey(item: item)

        // What RemoteChangeObserver does after clearing the caches: no item changed locally.
        ThumbnailCacheState.shared.invalidateAll()

        #expect(ThumbnailKey(item: item) != before)
        #expect(ThumbnailKey(item: item).modifiedDate == before.modifiedDate)
    }

    // MARK: - Three-way merge against the sheet's baseline

    @Test func untouchedFieldIsNotWrittenOverARemoteEdit() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        let opened = baseline(for: item, in: f)

        // iPad changes the year while the phone's sheet is open on the same item.
        try remoteEdit({ value(f.year, on: item)?.numberValue = 1986 }, in: f)

        // Phone edits only the title; its year draft still says 1979.
        var drafts = opened.fieldDrafts
        drafts[0].textValue = "Aliens"
        let outcome = try update(item, in: f, fieldDrafts: drafts, baseline: opened)

        #expect(outcome.fieldsChanged)
        #expect(value(f.title, on: item)?.textValue == "Aliens")
        #expect(value(f.year, on: item)?.numberValue == 1986, "the stale draft must not undo the remote edit")
        #expect(item.searchText.contains("1986"))
    }

    @Test func withoutABaselineEveryDraftIsApplied() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        try remoteEdit({ value(f.year, on: item)?.numberValue = 1986 }, in: f)

        _ = try update(item, in: f, fieldDrafts: drafts(for: f, title: "Aliens"))

        #expect(value(f.year, on: item)?.numberValue == 1979)
    }

    @Test func untouchedFieldWithNoStoredValueIsStillCreated() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        let yearValue = try #require(value(f.year, on: item))
        f.context.delete(yearValue)
        try f.context.save()
        #expect(value(f.year, on: item) == nil)

        let opened = baseline(for: item, in: f)
        let modifiedBefore = item.modifiedDate
        let outcome = try update(item, in: f, fieldDrafts: opened.fieldDrafts, baseline: opened,
                                 now: Date(timeIntervalSince1970: 1_900_000_000))

        #expect(value(f.year, on: item) != nil, "custom sort on Year only surfaces items with a value row")
        #expect(!outcome.fieldsChanged, "upkeep, not an edit")
        #expect(item.modifiedDate == modifiedBefore)
    }

    @Test func untouchedDraftForAFieldRemovedElsewhereCreatesNothing() throws {
        let f = try makeFixture()
        let item = try create(in: f)
        let opened = baseline(for: item, in: f)

        // The Year field is deleted on another device while the sheet is open.
        let yearValue = try #require(value(f.year, on: item))
        f.context.delete(yearValue)
        f.context.delete(f.year)
        try f.context.save()

        let outcome = try update(item, in: f, fieldDrafts: opened.fieldDrafts, baseline: opened)

        #expect(!outcome.fieldsChanged)
        #expect(item.fieldValues.count == 3)
    }

    @Test func untouchedNotesAreNotWrittenOverARemoteEdit() throws {
        let f = try makeFixture()
        let item = try create(in: f, notes: "phone")
        let opened = baseline(for: item, in: f)
        try remoteEdit({ item.notes = "ipad" }, in: f)

        let outcome = try update(item, in: f, notes: "phone", fieldDrafts: opened.fieldDrafts, baseline: opened)

        #expect(!outcome.notesChanged)
        #expect(item.notes == "ipad")
    }

    @Test func touchedNotesStillWin() throws {
        let f = try makeFixture()
        let item = try create(in: f, notes: "phone")
        let opened = baseline(for: item, in: f)
        try remoteEdit({ item.notes = "ipad" }, in: f)

        let outcome = try update(item, in: f, notes: "phone, revised", fieldDrafts: opened.fieldDrafts, baseline: opened)

        #expect(outcome.notesChanged)
        #expect(item.notes == "phone, revised")
    }

    @Test func photoAddedRemotelyWhileTheSheetWasOpenSurvivesTheSave() throws {
        let f = try makeFixture()
        let item = try create(in: f, photoDrafts: [PhotoDraft(imageData: try makePNGData(red: 0.1), priority: 0)])
        let opened = baseline(for: item, in: f)

        let remotePhoto = ItemPhoto(imageData: try makePNGData(red: 0.9), priority: 1)
        try remoteEdit({
            f.context.insert(remotePhoto)
            remotePhoto.item = item
        }, in: f)

        var drafts = opened.fieldDrafts
        drafts[0].textValue = "Aliens"
        let outcome = try update(item, in: f, fieldDrafts: drafts, photoDrafts: opened.photoDrafts, baseline: opened)

        #expect(!outcome.photosChanged)
        #expect(item.photos.count == 2)
    }

    @Test func photoRemovedByTheUserIsStillDeleted() throws {
        let f = try makeFixture()
        let item = try create(in: f, photoDrafts: [
            PhotoDraft(imageData: try makePNGData(red: 0.1), priority: 0),
            PhotoDraft(imageData: try makePNGData(red: 0.9), priority: 1),
        ])
        let opened = baseline(for: item, in: f)

        let outcome = try update(item, in: f, photoDrafts: Array(opened.photoDrafts.prefix(1)), baseline: opened)

        #expect(outcome.photosChanged)
        #expect(item.photos.count == 1)
    }

    @Test func untouchedPhotoDeletedRemotelyStaysDeleted() throws {
        let f = try makeFixture()
        let item = try create(in: f, photoDrafts: [PhotoDraft(imageData: try makePNGData(), priority: 0)])
        let opened = baseline(for: item, in: f)
        let stored = try #require(item.photos.first)
        try remoteEdit({ f.context.delete(stored) }, in: f)

        let outcome = try update(item, in: f, photoDrafts: opened.photoDrafts, baseline: opened)

        #expect(!outcome.photosChanged)
        #expect(item.photos.isEmpty)
    }

    @Test func untouchedPhotoKeepsARemoteCaption() throws {
        let f = try makeFixture()
        let item = try create(in: f, photoDrafts: [PhotoDraft(imageData: try makePNGData(), priority: 0)])
        let opened = baseline(for: item, in: f)
        try remoteEdit({ item.photos.first?.caption = "from ipad" }, in: f)

        let outcome = try update(item, in: f, photoDrafts: opened.photoDrafts, baseline: opened)

        #expect(!outcome.photosChanged)
        #expect(item.photos.first?.caption == "from ipad")
    }
}
