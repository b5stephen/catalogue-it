# Image Loading & Search Performance

## What's Already Done

- **P1** `@Attribute(.externalStorage)` on `ItemPhoto.imageData`
- **P3** Async decode off main thread — `ItemCardPhotoView` and `ItemThumbnailView` use `Task.detached(priority: .userInitiated)` inside `.task(id:)`
- **P5** `#Predicate` in fetches — `ItemPaginationController.makePredicate()` uses `#Predicate` with CONTAINS on a denormalised `searchText` field
- **P6** `LazyVGrid` — `ItemGridView` already uses it

## What Was Implemented

### Step 1 — Search Debounce · `CatalogueDetailView.swift`

Added `appliedSearchText` state. `searchText` binds to the search bar; `appliedSearchText` is written 200ms after the user stops typing. `CatalogueItemsView` receives `appliedSearchText`, so `pagination.reset()` (a full SwiftData fetch) only fires when the user pauses, not on every keystroke.

### Step 2 — NSCache for Decoded Images · `Utilities/ImageCache.swift`

Added a shared `actor ImageCache` backed by `NSCache<NSString, UIImage>`. `NSCache` automatically evicts entries under memory pressure. Both `ItemCardPhotoView` and `ItemThumbnailView` check the cache before decoding and store the result after. This prevents re-decoding the same image every time a cell scrolls back into view.

### Step 3 — Separate Thumbnail Field · `ItemPhoto`, `ImageHelpers`, `PhotoPickerView`, `CatalogueTransferData`

- `ItemPhoto` now stores a `thumbnailData: Data?` field (also with `.externalStorage`) alongside `imageData`.
- `ImageHelpers` gained `makeThumbnail(maxDimension:)` — cross-platform (iOS `UIGraphicsImageRenderer`, macOS `NSBitmapImageRep`), outputs a 300 × 300 JPEG at 0.7 quality.
- `PhotoPickerView` populates `thumbnailData` when saving a new photo.
- `CatalogueTransferData` populates `thumbnailData` when importing photos.
- List/grid thumbnail views use `thumbnailData` directly — full-res `imageData` is only loaded in detail/full-screen views.
