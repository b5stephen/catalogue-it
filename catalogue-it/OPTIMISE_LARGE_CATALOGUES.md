# Optimise Large Catalogues: DB-Level Sort & Search

## Why This Was Needed

The app uses an EAV (Entity-Attribute-Value) model: each catalogue item's field values are stored
as child rows in a separate `FieldValue` table rather than as columns on the item itself. This is
the right design for dynamic, user-defined fields — you can't know at compile time what columns
to add — but it creates a performance problem for sorting and searching.

**The core constraint:** SwiftData (and the SQLite underneath it) can only sort or filter by
columns on the table being queried. It cannot `ORDER BY` a value that lives in a child row. As a
result, the original implementation had to:

1. Load **all** items for a catalogue into memory
2. For each item, also load **all** of its `FieldValue` children
3. Apply search by scanning every field value in Swift
4. Apply custom-field sorts entirely in Swift via `CatalogueItemSort.sorted()`

For small catalogues this is fine. For catalogues with thousands of items it means the app loads
all that data before the user sees anything, and every search keystroke re-scans the whole set.

---

## The Approach: Two Denormalised Columns

Rather than changing the EAV model (which would require a major schema redesign and lose its
flexibility), the solution adds two derived columns that are kept in sync whenever an item is saved:

- **`FieldValue.sortKey`** — a normalised string that sorts correctly for any field type
- **`CatalogueItem.searchText`** — a lowercased blob of all field display values joined together

Both are indexed so SQLite can use them efficiently. The source-of-truth data (the typed value
columns) is untouched; these are purely derived caches.

---

## Changes Made

### `Utilities/SortKeyEncoder.swift` (new file)

Encodes any `FieldValue`'s typed value into a string that sorts correctly in byte order —
the only kind of sort SQLite can do natively.

The challenge is that each field type needs a different strategy to sort correctly as a string:

- **Text** — `lowercased()`. Simple; SQLite byte-order sort is approximately correct for ASCII.
  Non-ASCII text (accented characters, CJK) won't match Swift's `localizedCompare` — an accepted
  trade-off to avoid storing ICU sort keys.

- **Number** — add a large offset (`1e12`) to shift all practical values into positive territory,
  then format as a zero-padded fixed-width decimal string. Without the offset, negative numbers
  would sort after positive ones because `"-"` < `"0"` in byte order but `-1 < 1` numerically.
  With the offset, `-5 + 1e12 = 999999999995` and `1234 + 1e12 = 1000000001234`, which sort
  correctly as strings.

- **Date** — ISO 8601 (`YYYY-MM-DDTHH:MM:SSZ`). This format is intentionally designed to sort
  correctly as a plain string; no special treatment needed.

- **Boolean** — `"0"` or `"1"`. Single character, sorts correctly.

- **Nil / missing value** — `"\u{FFFF}"`, the highest Unicode scalar. This ensures items with no
  value for a field always sort last in ascending order, which matches the existing in-memory
  behaviour of `CatalogueItemSort`.

### `Utilities/SearchTextBuilder.swift` (new file)

Builds the `searchText` blob for an item by calling `displayValue()` on each of its
`FieldValue`s, joining the results with spaces, and lowercasing the whole thing. Using the
existing `displayValue()` method means numbers are formatted (e.g. `"29.99"` not `"29.99000"`),
dates are human-readable, and booleans become `"yes"` or `"no"` — exactly what a user would type
when searching.

### `Models/FieldValue.swift`

Added `var sortKey: String` with a default of `SortKeyEncoder.missingValueSentinel` and a
compound `#Index` on `(fieldDefinition, sortKey)`.

The compound index is what makes DB-level custom-field sort efficient. When the view queries
`FieldValue` filtered to a specific `fieldDefinition` and sorted by `sortKey`, SQLite can satisfy
the entire query from that index without touching the main table rows.

Adding a property with a default value does not require a `SchemaMigrationPlan` — SwiftData adds
the column automatically on next launch. Rows for existing items will have the sentinel value
until those items are next saved through the edit sheet.

### `Models/CatalogueItem.swift`

Added `var searchText: String = ""` and extended the `#Index` macro to include
`[\.deletedDate, \.searchText]`.

The compound index pairs `deletedDate` with `searchText` because every search query also filters
out soft-deleted items (`deletedDate == nil`). The compound index lets SQLite resolve both
conditions in a single index scan rather than filtering deleted items as a second pass.

Same migration behaviour as `FieldValue` — no migration plan needed, existing rows get `""`.

### `Items/AddEditItemView.swift`

`saveItem()` already deleted and recreated all `FieldValue` objects on every save (both create
and edit paths), so the only change needed was to compute `sortKey` for each `FieldValue` as it
is constructed, and then compute `searchText` on the item after all values are built.

The edit path's delete-and-recreate pattern is convenient here: there's no need to diff old
vs new values; the derived columns are always rebuilt from scratch.

### `Catalogues/CatalogueItemsView.swift`

Two changes to the query layer:

**Search is now DB-level.** The `@Query` predicate was extended with
`&& (!hasSearch || item.searchText.contains(lowercasedQuery))`. SwiftData translates
`String.contains` to a SQLite `LIKE '%query%'` scan. This is still O(n) at the SQLite level
(no full-text index), but SQLite does the scanning — items that don't match never enter Swift
memory at all. Previously every item was loaded and then filtered in Swift.

**Custom-field sort is now DB-level.** `computeDisplayedItems()` previously called
`CatalogueItemSort.sorted()` which loaded all items and sorted them in Swift. It now uses
`modelContext.fetch` on `FieldValue` with a `sortBy: [SortDescriptor(\.sortKey)]` descriptor.
SQLite sorts using the `(fieldDefinition, sortKey)` index and returns rows already in order.

The FieldValue fetch is intentionally kept simple — it predicates on `fieldDefinition.fieldID`,
`deletedDate`, and `isWishlist`, but not on catalogue or search text. The `@Query` result set
(which is already filtered by catalogue, tab, and search) is used as a candidate allow-list:
only items present in that set are kept from the sorted FieldValue results. This two-step
approach avoids a three-level relationship traversal (`fv → item → catalogue`) in the FieldValue
predicate, which SwiftData may or may not optimise well.

### `Utilities/CatalogueTransferData.swift`

The importer's `makeCatalogue(in:priorityOffset:)` builds `FieldValue` objects the same way
`AddEditItemView.saveItem()` does. Without updating it, any catalogue imported from a pre-change
export file would have `sortKey = "\u{FFFF}"` and `searchText = ""` on all items — they would
sort last in every custom-field view and never appear in search results.

The fix mirrors the `AddEditItemView` change exactly: collect created `FieldValue` objects,
set `sortKey` on each, then set `searchText` on the item after the loop.

---

## Known Limitations

- **Text sort is byte-order, not locale-aware.** SQLite sorts strings as raw bytes; this differs
  from Swift's `localizedCompare` for non-ASCII characters (accented letters, CJK scripts). For
  catalogues with predominantly ASCII field values this is unnoticeable.

- **Existing items need a re-save to backfill.** Items created before this change have
  `sortKey = "\u{FFFF}"` and `searchText = ""`. They will sort last and not appear in search
  until opened in the edit sheet and saved. A future improvement could add a one-time migration
  that recomputes these values for all existing items on first launch.

- **New field definitions don't retroactively create FieldValue rows.** If a field is added to a
  catalogue after items already exist, those items have no `FieldValue` row for the new field and
  therefore no `sortKey` entry. They will be absent from custom-field sort results for that field
  until edited. This is a pre-existing model constraint, not introduced by this change.

- **Pagination is not wired to the UI.** The `FetchDescriptor`s used in `CatalogueItemsView` now
  support `fetchLimit` and `fetchOffset` correctly (because sort is DB-level), but the view still
  loads all matching items. Hooking up paginated scroll is a separate future task.
