# Optimise Large Catalogues: DB-Level Sort & Search

## Context

The current EAV (Entity-Attribute-Value) model stores field values in a child table (`FieldValue`).
This means SwiftData cannot push custom-field sorting or text search to SQLite — everything happens
in-memory after all items are loaded. For catalogues with thousands of items this causes sluggishness.

The fix adds two denormalised columns kept in sync with the source data:
- `FieldValue.sortKey` — a normalised, lexicographically sortable string representation of the value
- `CatalogueItem.searchText` — a lowercased, space-joined blob of all field display values

With these columns properly indexed, SQLite can sort and filter without loading items into memory,
and `FetchDescriptor.fetchLimit`/`fetchOffset` enable true pagination.

---

## Step 1 — Utility: SortKeyEncoder

**File to create:** `catalogue-it/Utilities/SortKeyEncoder.swift`

Create an enum with a single static method `sortKey(for: FieldValue) -> String`.

Encoding strategy per field type:

| Type    | Strategy | Example output |
|---------|----------|----------------|
| Text    | `lowercased()`, sentinel if nil/empty | `"blue"` |
| Number  | `value + 1e12`, then `String(format: "%021.6f", ...)` | `"01000001234.500000"` |
| Date    | ISO 8601 via `ISO8601DateFormatter` | `"2024-03-15T00:00:00Z"` |
| Boolean | `"0"` or `"1"` | `"1"` |
| Nil/missing | `"\u{FFFF}"` — sorts last | `"\u{FFFF}"` |

The number offset trick: adding `1e12` to every number makes all practical values positive,
so zero-padded strings sort correctly even for negatives (e.g. `-5 + 1e12 = 999999999995`).

```swift
// catalogue-it/Utilities/SortKeyEncoder.swift

import Foundation

enum SortKeyEncoder {
    static let missingValueSentinel = "\u{FFFF}"
    private static let numberOffset: Double = 1e12
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f
    }()

    static func sortKey(for fieldValue: FieldValue) -> String {
        switch fieldValue.fieldType {
        case .text:
            guard let text = fieldValue.textValue, !text.isEmpty else { return missingValueSentinel }
            return text.lowercased()
        case .number:
            guard let n = fieldValue.numberValue else { return missingValueSentinel }
            return String(format: "%021.6f", n + numberOffset)
        case .date:
            guard let d = fieldValue.dateValue else { return missingValueSentinel }
            return iso8601.string(from: d)
        case .boolean:
            guard let b = fieldValue.boolValue else { return missingValueSentinel }
            return b ? "1" : "0"
        }
    }
}
```

**No other files change in this step.**

---

## Step 2 — Utility: SearchTextBuilder

**File to create:** `catalogue-it/Utilities/SearchTextBuilder.swift`

Create an enum with a single static method `build(from: [FieldValue]) -> String`.

```swift
// catalogue-it/Utilities/SearchTextBuilder.swift

import Foundation

enum SearchTextBuilder {
    /// Lowercased, space-joined display values for all field values.
    /// Stored on CatalogueItem so SQLite can filter without loading child rows.
    static func build(from fieldValues: [FieldValue]) -> String {
        fieldValues
            .map { $0.displayValue() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
```

**No other files change in this step.**

---

## Step 3 — Model: Add `sortKey` to `FieldValue`

**File to edit:** `catalogue-it/Models/FieldValue.swift`

Add one stored property and one index macro:

```swift
@Model
final class FieldValue {
    // NEW — add this index macro before the properties:
    #Index<FieldValue>([\.fieldDefinition, \.sortKey])

    // ... existing properties unchanged ...

    // NEW — add after boolValue:
    /// Normalised, lexicographically sortable string. Computed from the typed value on save.
    /// "\u{FFFF}" when the field has no value (sorts last).
    var sortKey: String = SortKeyEncoder.missingValueSentinel
}
```

**SwiftData migration note:** Adding a property with a default value does not require an explicit
`SchemaMigrationPlan`. SwiftData will add the column with the default on next launch.
Existing rows will have `sortKey = "\u{FFFF}"` until items are re-saved through the edit flow.

**No other files change in this step.**

---

## Step 4 — Model: Add `searchText` to `CatalogueItem`

**File to edit:** `catalogue-it/Models/CatalogueItem.swift`

Add one stored property and extend the existing `#Index` macro:

```swift
@Model
final class CatalogueItem {
    // REPLACE existing #Index line with:
    #Index<CatalogueItem>(
        [\.isWishlist],
        [\.createdDate],
        [\.isWishlist, \.createdDate],
        [\.deletedDate],
        [\.deletedDate, \.isWishlist],
        [\.deletedDate, \.searchText]   // NEW: enables DB-level search + soft-delete filter
    )

    // ... existing properties unchanged ...

    // NEW — add after deletedDate:
    /// Lowercased, space-joined concatenation of all field display values.
    /// Updated on every item save. Enables DB-level CONTAINS predicate.
    var searchText: String = ""
}
```

**Same migration note as Step 3 — no explicit migration plan needed.**

**No other files change in this step.**

---

## Step 5 — Save Flow: Populate `sortKey` and `searchText`

**File to edit:** `catalogue-it/Items/AddEditItemView.swift`

In `saveItem()`, after constructing each `FieldValue` and setting its typed value, compute and
assign its `sortKey`. After all `FieldValue` objects are created, build and assign `searchText`
on the item.

Key change in the field-value creation loop:

```swift
// After setting the typed value on fv, add:
fv.sortKey = SortKeyEncoder.sortKey(for: fv)
fv.item = targetItem
modelContext.insert(fv)
createdFieldValues.append(fv)  // collect for searchText build
```

Then after the loop:

```swift
targetItem.searchText = SearchTextBuilder.build(from: createdFieldValues)
```

The existing edit path deletes and recreates all `FieldValue` objects, so no special handling
is needed for edits — the new values will always have correct `sortKey`s and `searchText`
will be recomputed from scratch.

**Files changed:** `AddEditItemView.swift` only.

---

## Step 6 — View: DB-Level Search and Sort in `CatalogueItemsView`

**File to edit:** `catalogue-it/Catalogues/CatalogueItemsView.swift`

This is the largest change. Two things to update:

### 6a — DB-level search predicate

Add `searchText` filtering to the existing `#Predicate` in `init`:

```swift
let hasSearch = !searchText.isEmpty
let lowercasedQuery = searchText.lowercased()

// Add to predicate:
&& (!hasSearch || item.searchText.contains(lowercasedQuery))
```

This moves the search filter from in-memory Swift to a SQLite LIKE scan.
Only items that match are ever materialised in memory.

### 6b — DB-level custom field sort via `FieldValue`

Add `@Environment(\.modelContext) private var modelContext` to the view.

Replace the in-memory sort branch in `computeDisplayedItems()` with a `modelContext.fetch`
on `FieldValue`, sorted by `sortKey` at the DB level:

```swift
private func computeDisplayedItems() -> [CatalogueItem] {
    let field = ItemSortField(rawValue: sortFieldKey)

    // dateAdded: @Query already applied DB-level sort — nothing to do.
    guard case .field(let fieldID) = field else { return items }

    // Custom field: fetch FieldValues sorted by sortKey at DB level.
    let ascending = (ItemSortDirection(rawValue: sortDirection) ?? .ascending) == .ascending
    let filterAll = tab == .all
    let filterWishlist = tab == .wishlist

    var descriptor = FetchDescriptor<FieldValue>(
        predicate: #Predicate { fv in
            fv.fieldDefinition?.fieldID == fieldID
            && fv.item?.deletedDate == nil
            && (filterAll || fv.item?.isWishlist == filterWishlist)
        },
        sortBy: [SortDescriptor(\.sortKey, order: ascending ? .forward : .reverse)]
    )
    descriptor.relationshipKeyPathsForPrefetching = [\.item]

    // Use the @Query result set (already search-filtered) as an allow-list.
    // This avoids a complex 3-level predicate traversal in the FieldValue fetch.
    let candidateIDs = Set(items.map(\.persistentModelID))

    do {
        let sorted = try modelContext.fetch(descriptor)
        return sorted.compactMap { $0.item }.filter { candidateIDs.contains($0.persistentModelID) }
    } catch {
        return items  // graceful fallback
    }
}
```

**Files changed:** `CatalogueItemsView.swift` only.

---

## Step 7 — Commit and Push

After all steps pass a type-check build, commit with a clear message and push to the feature branch.

```bash
xcodebuild -project catalogue-it.xcodeproj -scheme catalogue-it -configuration Debug build
git add catalogue-it/Utilities/SortKeyEncoder.swift
git add catalogue-it/Utilities/SearchTextBuilder.swift
git add catalogue-it/Models/FieldValue.swift
git add catalogue-it/Models/CatalogueItem.swift
git add catalogue-it/Items/AddEditItemView.swift
git add catalogue-it/Catalogues/CatalogueItemsView.swift
git commit -m "Add DB-level sort and search for large catalogue support"
git push -u origin claude/optimize-catalogue-data-models-LPb6O
```

---

## Known Limitations

- **Text sort locale accuracy**: SQLite sorts strings byte-by-byte; this differs from Swift's
  `localizedCompare` for non-ASCII text. Acceptable trade-off for now.
- **Backfill on first open**: Existing items will have `sortKey = "\u{FFFF}"` and
  `searchText = ""` until they are re-saved through the edit sheet.
- **New FieldDefinitions on existing items**: Adding a new field to a catalogue does not
  retroactively create `FieldValue` rows for existing items. These items will be missing from
  custom-field sort queries until edited. A future improvement could add a migration step.
- **Pagination not wired up**: The fetch descriptors support `fetchLimit`/`fetchOffset` but
  the view does not yet implement a paginated scroll. That is a separate future task.
