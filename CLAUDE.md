# Catalogue-It

A multi-platform SwiftUI collection management app for iOS, iPadOS, and macOS. Users can create custom catalogues (e.g., model planes, stamps, books) with flexible field definitions, photo attachments, and iCloud sync.

Performance and user customisation are key considerations. The app must be able to support small catalogues as well as larger ones containing many photos, custom fields and 2000+ items.

**No external dependencies** — all frameworks are Apple built-ins.

## Project Structure

All code files must be placed in the catalogue-it subfolder. Never place files in the Xcode project root group. Follow the existing feature-based subdirectories. Tests have their own folders: `UITests/` and `UnitTests/`.

**Key design decisions:**

- `FieldValue` denormalizes field name and type to prevent data loss if definitions change
- Photos stored as `Data` directly in SwiftData
- All ordered collections use an explicit `sortOrder: Int` field

## Code Comments

Comments are succinct and only state what the code cannot.

- **Don't restate the code.** No "Convenience accessor for…", "Header row", or a doc comment that
  paraphrases the name and signature.
- **State the reason, not the history.** No "previously…", "this used to…", "(bug 4)", build
  numbers or debugging narrative; keep only the constraint that remains true, in the present tense.
- **Keep what prevents a bug.** Platform quirks, invariants, sync and SwiftData constraints, and why
  a non-obvious choice was made (e.g. the `fetchHistory` ban, `nonisolated` on stored `Codable`
  types, compare-before-assign) stay — trimmed to their essentials.
- **Put it where it applies.** A comment explaining a function sits on that function, not its
  neighbour.
- **Keep it true.** When changing code, update or delete any comment it makes wrong; a stale comment
  is worse than none.
- Long-form rationale belongs in this file, not repeated across source files.

## iCloud Sync

Backed by CloudKit through SwiftData's built-in mirroring.

- The capability lives in `catalogue-it/catalogue-it.entitlements` (container
  `iCloud.dev.etched.catalogue-it`), wired up via `CODE_SIGN_ENTITLEMENTS`. `catalogue_itApp.swift`
  passes `cloudKitDatabase: .automatic`, which adopts the container named there — the container id
  is deliberately not repeated in Swift. UI-test runs pass `.none`, since CloudKit and an
  in-memory store are not a valid combination.
- `UIBackgroundModes = remote-notification` lets the store receive pushed changes. It lives in
  `Config/Info.plist` (merged with the keys Xcode generates from `INFOPLIST_KEY_*`), because the
  generator silently ignores `INFOPLIST_KEY_UIBackgroundModes` — the setting is read but never
  reaches the built plist. The file sits outside `catalogue-it/` so the file-system-synchronized
  group doesn't also copy it in as a resource.
- SwiftData handles conflict resolution automatically (last writer wins, per property —
  confirmed on device Sept 2026). Each `FieldValue` is its own record, so two devices editing
  different fields of one item never conflict. The remaining seams are the derived columns
  and the edit sheet, below.

### Model constraints — breaking these breaks sync *and* local data

- Every non-optional property must have a default value.
- Every relationship must be optional, **including to-many**. `[Foo] = []` is rejected at
  container load. The persisted properties are therefore `storedItems`, `storedFieldDefinitions`,
  `storedFieldValues` and `storedPhotos`; extensions expose the non-optional `items`,
  `fieldDefinitions`, `fieldValues` and `photos` the rest of the app uses. Those accessors must
  stay in extensions — the `@Model` macro rewrites every `var` in a class body into a persisted
  accessor, computed properties included, which crashes at runtime on first access.
- Never use `@Attribute(.unique)` or `#Unique`.
- Every `Codable` type stored on a model — `FieldOptions` and everything it wraps,
  `CatalogueLayoutOptions` — must be declared `nonisolated`. The project defaults to main-actor
  isolation, and an isolated `Codable` conformance is invisible (`as? any Encodable` is nil)
  from off the main actor, where SwiftData may encode. `FieldOptionsPersistenceTests` checks
  each type from off the main actor; add new ones there. (The Sept 2026 wipe of every field's
  options was ultimately `fetchHistory`, below — this rule stays because the check is real.)
- **Never call `ModelContext.fetchHistory`.** On iOS 26.5 and 27.0 one call — any context,
  any descriptor, result unused — leaves every container *in the process* (not just the
  caller's) writing every composite column (`fieldOptions`, `layoutOptions`) of a dirty row as
  NULL from the second save on. That is what wiped option lists and flag icons in Sept 2026.
  Read persistent history through `PersistentHistoryReader` (Core Data, via the coordinator the
  remote-change notification carries). `FieldOptionsPersistenceTests.fetchHistoryStillWipesComposites`
  is a known-issue test that will start failing when Apple fixes it. Because it poisons the
  whole test process it is opt-in: run it alone with `TEST_RUNNER_FETCHHISTORY_CANARY=1`
  (command in the test's doc comment) after an Xcode or OS update.
- `#Index`, `@Attribute(.externalStorage)` (maps to CKAsset) and `Codable` enums with associated
  values are all fine.
- Key paths handed to SwiftData — `#Predicate`, `relationshipKeyPathsForPrefetching`,
  `propertiesToFetch` — must name the persisted `stored…` property, not the accessor. And
  `contains(where:)` over an optional to-many cannot be expressed in `#Predicate` at all; query
  from the child side instead (see `ItemPaginationController.customSortMatchingCount`).

### Reacting to synced-in changes

Local writes keep derived state in step; a change merged from another device does not.
`RemoteChangeObserver` observes `NSPersistentStoreRemoteChange` (debounced) and rebuilds what
sync bypasses: facet mirrors for catalogues whose field configuration changed, the thumbnail
caches, and the pending-deletion sweep, then posts `.remoteChangesMerged`. Add to it whenever
new derived state is introduced. It also keeps the coordinator that notification carries as
its `object` — the only handle on the Core Data stack SwiftData gives us, and what
`PersistentHistoryReader` reads history through.

- A value merged in by CloudKit bypasses the model setters, so SwiftData observation does not
  fire for it, and SwiftUI will not re-run a row whose only input is the same model instance.
  A mounted view that must reflect a remote edit has to read an observed generation in `body`
  (`ThumbnailCacheState.generation`, which the rows already read via `ThumbnailKey`).
- `NSManagedObjectContextDidSave` *does* fire for the mirroring context's merges, but the
  pagination controller's count guard hides edits; it reloads on `.remoteChangesMerged`
  instead, without the guard. Reloads must keep the loaded depth — on iPad the list stays
  mounted, and truncating to one page clamps anyone scrolled past it.
- The remote-change pass also runs ~1.5s after every local save on an iCloud device: after
  export, the mirroring context writes CloudKit system fields back. Work hung on it must be
  cheap and must not disturb scroll or selection.
- The Simulator receives no APNs pushes. Remote-merge behaviour only shows on real devices.

### Derived columns and merges

`FieldValue.sortKey`/`tiebreakKey`, `CatalogueItem.searchText`, `statusValue` and `flagKeys`
are computed from an item's *whole* set of values, and they sync. A field edited on another
device arrives alone, so everything derived from it here is stale until
`RemoteChangeObserver` recomputes the affected items (found through persistent history:
`FieldValue` inserts/content updates not authored by the main context, whose `author` is set
for that purpose; items are matched back by `createdDate`, since a Core Data object ID cannot
become a `PersistentIdentifier`). That recompute is itself exported, which is only safe
because of three rules every write path must keep:

- **Deterministic across devices.** Anything locale-, language-, clock- or *order*-dependent
  in a synced derived column makes two devices rewrite each other forever. So:
  `SearchTextBuilder` writes a canonical, locale-free blob (numbers ungrouped, dates as the
  GMT days of the instant ±14h, booleans omitted, values ordered by field priority) and
  `queryVariants` folds the query to match; field definitions are always ordered with
  `Catalogue.sortedFieldDefinitions` / `FieldDefinition.isOrderedBefore` (equal priorities
  happen when two devices add a field before a merge); and duplicate `FieldValue`s for one
  definition are read through `SortKeyEncoder.preferredValue`, never `first(where:)`. Bump
  `SearchTextBuilder.formatVersion` when the blob rules change; `DerivedDataBackfill`
  rewrites the column once per device.
- **Compare before assign.** All recomputation goes through `ItemDerivedColumns.refresh`, which
  writes only what differs, so an already-correct item stays clean and the round trip stops.
  Never bump `modifiedDate` from a recompute.
- **Not the user's to undo.** Recompute passes run inside
  `ModelContext.withUndoRegistrationSuspended`; on the undo stack they would put stale values
  back and export them.

The edit sheet's drafts are a copy of the item as of opening, not the user's intent, so
`ItemSaveService` takes the `EditBaseline` the sheet loaded and skips any draft equal to it —
otherwise a stale draft writes over a value that merged in while the sheet was open.

### Schema changes

Schema versions are pinned in `Models/SchemaVersions.swift`; add a version and a migration stage
there for any post-release model change.

**Any model property added, removed or retyped requires a CloudKit schema deploy before the next
TestFlight/App Store build** — Production never creates record types or fields on its own, and
skipping it fails sync with `partialFailure`. Steps are in the `cloudkit-schema-deploy` skill.

Sync status UI and field diagnostics rules live in `.claude/rules/sync-status-ui.md`.
