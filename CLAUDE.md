# Catalogue-It

A multi-platform SwiftUI collection management app for iOS, iPadOS, and macOS. Users can create custom catalogues (e.g., model planes, stamps, books) with flexible field definitions, photo attachments, and iCloud sync.

Performance and user customisation are key considerations. The app must be able to support small catalogues as well as larger ones containing many photos, custom fields and 2000+ items.

## Tech Stack

- **Language:** Swift 6
- **UI:** SwiftUI
- **Persistence:** SwiftData (with iCloud sync)
- **Platform targets:** iOS 26+, iPadOS 26+, macOS 26+
- **No external dependencies** — all frameworks are Apple built-ins

## Project Structure

All code files must be placed in the catalogue-it subfolder. Never place files in the Xcode project root group. Follow a feature-based subdirectories structure like below. Test have their on folders

```
catalogue-it/
├── catalogue_itApp.swift          # App entry point, SwiftData ModelContainer setup
├── Localizable.xcstrings          # Localization strings
├── Assets.xcassets/               # App resources (icons, colors)
├── Catalogues/                    # Catalogue list and detail views
├── Fields/                        # Field definition UI
├── Items/                         # Item management and display views
├── Models/                        # SwiftData model definitions
├── Photos/                        # Photo management views
├── Types/                         # Supporting enums and value types
└── Utilities/                     # Shared helpers and extensions
UITests/                           # All UI Tests live here
UnitTests/                         # All Unit Tests live here
catalogue-it.xcodeproj/            # Xcode project configuration
```

**Key design decisions:**

- `FieldValue` denormalizes field name and type to prevent data loss if definitions change
- Photos stored as `Data` directly in SwiftData
- All ordered collections use an explicit `sortOrder: Int` field

## Build & Run

```bash
# Open in Xcode
open catalogue-it.xcodeproj

# Command-line build
xcodebuild -project catalogue-it.xcodeproj -scheme catalogue-it -configuration Debug build

# Type-check only (fast)
swiftc -typecheck catalogue-it/*.swift
```

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
- SwiftData handles conflict resolution automatically (last writer wins, per property).

### Model constraints — breaking these breaks sync *and* local data

- Every non-optional property must have a default value.
- Every relationship must be optional, **including to-many**. `[Foo] = []` is rejected at
  container load. The persisted properties are therefore `storedItems`, `storedFieldDefinitions`,
  `storedFieldValues` and `storedPhotos`; extensions expose the non-optional `items`,
  `fieldDefinitions`, `fieldValues` and `photos` the rest of the app uses. Those accessors must
  stay in extensions — the `@Model` macro rewrites every `var` in a class body into a persisted
  accessor, computed properties included, which crashes at runtime on first access.
- Never use `@Attribute(.unique)` or `#Unique`.
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
caches, and the pending-deletion sweep. Add to it whenever new derived state is introduced.

### Sync status UI

`CloudKitSyncMonitor` reads `NSPersistentCloudKitContainer.eventChangedNotification` (again with
`object: nil`, since SwiftData doesn't expose the container). Events carry only a type, start/end
dates, a success flag and an error — **no record counts and no percentage**, so progress is
necessarily indeterminate; the item count in `SyncStatusBar` is counted from our own store as rows
land. Two behaviours worth preserving:

- Signed out of iCloud, CloudKit posts an import event that *starts and never finishes*. The
  monitor gates on `CKContainer.default().accountStatus()` so the indicator doesn't sit on
  "Syncing…" forever for anyone not using iCloud.
- Both directions are shown: `.import`/`.setup` as "Syncing from iCloud · N items", `.export`
  as "Syncing to iCloud" with no count (the local total says nothing about what is still queued).
- The bar lives on the catalogue list only. An inset on the `NavigationSplitView` doesn't reach
  columns pushed onto their own stack in compact width, and on the item screen iOS 26 renders
  `.searchable` as a bottom bar occupying the same edge.
- Not-signed-in, network and throttling errors are deliberately **not** surfaced — they are either
  the user's choice or self-resolving. Only actionable failures (quota, schema) reach the UI.

Schema versions are pinned in `Models/SchemaVersions.swift`; add a version and a migration stage
there for any post-release model change.

### Deploying the CloudKit schema — required before every TestFlight/App Store build

TestFlight and App Store builds talk to the **Production** CloudKit environment, which never
creates record types or fields on its own. Development does — but only for fields it has
actually seen exported, and a `CKRecord` carries no entry for a nil value. A field nobody
happened to populate while testing is therefore missing from *both* environments, so comparing
Development against Production shows no diff while Production is still behind the model. The
comparison that matters is model vs Production.

So, whenever a model property is added, removed or retyped:

1. Debug build (Simulator signed into iCloud) → hammer menu → **Validate CloudKit Schema**.
   Dry run; prints the complete record-type and field listing to the Xcode console.
2. Same menu → **Push CloudKit Schema (Dev)**. This runs `initializeCloudKitSchema`, which
   covers every entity and attribute from the model rather than from what got typed in.
3. CloudKit Console → Schema → **Deploy Schema Changes** to push Development to Production.
   Additive-only, so it cannot break existing production data.

Skipping this produces `BAD_REQUEST` in the CloudKit Console logs and, on the client, a
`partialFailure` — the bare `CKErrorDomain error 2` that started this. `CloudKitSchemaInitializer`
(DEBUG only) holds the details.

### Reporting sync failures from the field

`CKError.partialFailure` (code 2) is a container, not a cause — the per-record errors are in
`userInfo[CKPartialErrorsByItemIDKey]`. `SyncDiagnostics` unwraps them, buckets them by
(code, record type), scrapes the `CD_…` field names out of the server messages, and keeps a
rolling record that survives a relaunch. `SyncDiagnosticsView` renders it for screenshotting,
because a screenshot is the only payload TestFlight feedback carries — there is no API to
attach anything else. Two rules for anything added there:

- Log at `.notice` or above with `privacy: .public`. `.debug` entries are memory-only and can
  never be recovered from a tester's device, and interpolations are redacted by default.
- Record every failure, including ones deliberately kept out of the UI. Staying quiet about a
  self-resolving error is a separate decision from discarding the evidence.
