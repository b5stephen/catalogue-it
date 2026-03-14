# Catalogue-It Development Plan

**App Overview:** A multi-platform catalogue app that lets users create custom catalogues with flexible field definitions, photos, and wishlist support. Built with SwiftUI and SwiftData with iCloud sync.

**Created:** February 20, 2026  
**Last Updated:** March 15, 2026

---

## 📋 Project Status

### ✅ Phase 1: Foundation - Data Models (COMPLETE)
**Status:** ✅ Done

#### What's Built:
- **SwiftData Models** (`Item.swift`):
  - `Catalogue` - Main collection container with icon and color customization
  - `FieldDefinition` - Defines custom fields for each catalogue
  - `CatalogueItem` - Individual items (owned or wishlist)
  - `FieldValue` - Type-safe storage for field data (text, number, date, boolean)
  - `ItemPhoto` - Photo attachments with sorting and captions
  - `FieldType` enum - Defines available field types

#### Key Features:
- ✅ Cascade delete rules (no orphaned data)
- ✅ Computed properties (`ownedItems`, `wishlistItems`, `displayName`, `primaryPhoto`)
- ✅ Type-safe value handling per field type
- ✅ Denormalized field info (values remember their definition)
- ✅ iCloud sync ready (SwiftData configuration)

#### Files:
- `Item.swift` - All data models
- `catalogue_itApp.swift` - Model container setup

---

### ✅ Phase 2: Catalogue Management UI (COMPLETE)
**Status:** ✅ Done

#### What's Built:
- **Add/Edit Catalogue Sheet** (`AddEditCatalogueView.swift`):
  - Create new catalogues with custom names
  - Icon picker with 80+ curated SF Symbols in 10 categories
  - Color picker for personalization
  - Custom field editor (add, reorder, delete)
  - Live preview of icon + color
  - Edit existing catalogues

- **Catalogue List** (`ContentView.swift`):
  - List view of all catalogues
  - Shows icon, name, owned count, wishlist count
  - Empty state view
  - Swipe to delete
  - Navigation to detail view

#### Key Features:
- ✅ Platform-aware code (iOS, iPadOS, macOS)
- ✅ Field management with drag-to-reorder
- ✅ Color-coded field types (blue=text, green=number, orange=date, purple=boolean)
- ✅ Validation (requires name and at least one field)
- ✅ Smart defaults (new catalogues start with "Name" text field)

#### Files:
- `AddEditCatalogueView.swift` - Catalogue creation/editing
- `ContentView.swift` - Home screen with catalogue list

---

## 🚀 Next Steps

### ✅ Phase 3: Catalogue Detail Screen (COMPLETE)
**Status:** ✅ Done

#### What's Built:
- **`CatalogueDetailView.swift`** — Owned/Wishlist tabs (segmented picker), grid/list toggle with `@AppStorage` persistence, empty state, platform-aware toolbar, navigation to Phase 4/5 placeholders
- **`ItemCardView.swift`** — 160px fixed-width grid card with photo thumbnail (150px) or placeholder, item name, rounded corners + shadow, cross-platform image handling
- **`ItemRowView.swift`** — List row with 56×56 thumbnail, headline name, top-2 field summaries via `fieldSummaries` computed property, cross-platform image support
- **`ContentView.swift`** — Simplified from 117 to 59 lines; removed placeholder detail, now navigates directly to `CatalogueDetailView`

#### Key Features:
- ✅ Grid/list layout preference persisted via `@AppStorage("itemLayoutPreference")`
- ✅ Tab filtering by `isWishlist`
- ✅ Contextual empty states per tab
- ✅ Cross-platform image handling (UIImage/NSImage)
- ✅ Placeholder navigation for Phase 4 (Add Item) and Phase 5 (Item Detail)

#### Files:
- `CatalogueDetailView.swift`
- `ItemCardView.swift`
- `ItemRowView.swift`
- `ContentView.swift` (simplified)

---

### ✅ Phase 4: Add/Edit Items (COMPLETE)
**Status:** ✅ Done

#### What's Built:
- **`AddEditItemView.swift`** — Dynamic form driven by the catalogue's field definitions; handles create and edit paths; `defaultIsWishlist` pre-selects the wishlist toggle when opened from the Wishlist tab
- **`FieldInputView.swift`** — Reusable control that renders `TextField`, `DatePicker`, or `Toggle` based on `FieldType`; platform-specific keyboard and autocapitalisation modifiers
- **`PhotoPickerView.swift`** — Form section with `PhotosPicker` (up to 10 images), horizontal thumbnail strip, per-photo caption `TextField`, delete button, JPEG compression via `compressedAsJPEG(quality:)`, `sortOrder` renumbering on delete
- **`FieldDefinitionDraft.swift`** — Added `FieldValueDraft` (form state for a single field, `numberText: String` for partial input) and `PhotoDraft` (form state for a photo)
- **`ImageHelpers.swift`** — Added cross-platform `compressedAsJPEG(quality:)` extension on `Data`
- **`CatalogueDetailView.swift`** — Replaced placeholder sheet with `AddEditItemView`, wiring `defaultIsWishlist: selectedTab == .wishlist`

#### Key Features:
- ✅ Dynamic form — renders one row per field definition in `sortOrder` order
- ✅ All four field types: text, number (string binding, parsed on save), date, boolean
- ✅ Number display strips trailing `.0` (e.g. `1969.0` → `"1969"`)
- ✅ Photo management: pick, thumbnail, caption, delete, compressed JPEG storage
- ✅ Wishlist toggle with tab-aware default
- ✅ Notes field (multi-line, saves as `nil` when empty)
- ✅ Edit mode pre-populates all fields and photos from the existing item
- ✅ Save deletes-and-recreates field values and photos (mirrors catalogue edit pattern)
- ✅ Cross-platform (iOS + macOS)

#### Files Created/Modified:
- `AddEditItemView.swift` (new)
- `FieldInputView.swift` (new)
- `PhotoPickerView.swift` (new)
- `FieldDefinitionDraft.swift` (added `FieldValueDraft`, `PhotoDraft`)
- `ImageHelpers.swift` (added `compressedAsJPEG`)
- `CatalogueDetailView.swift` (wired sheet)

---

### ✅ Phase 5: Item Detail Screen (COMPLETE)
**Status:** ✅ Done

#### What's Built:
- **`ItemDetailView.swift`** — Scrollable detail view with photo carousel (when photos exist), field values displayed with colour-coded type icons, notes section; toolbar with Edit, Share (`ShareLink` with computed text), Delete (confirmation dialog), and Move to Owned/Wishlist toggle; delete cascades via `modelContext.delete` and dismisses
- **`PhotoCarouselView.swift`** — `TabView` with `.page` style (iOS) / default (macOS), caption overlay per page, tap to open full-screen viewer; `fullScreenCover` on iOS, `sheet` on macOS
- **`FullScreenPhotoView.swift`** — Black background full-screen viewer with paged `TabView`, caption overlay per photo, dismiss button and per-photo `ShareLink` via `PhotoTransferable` (`DataRepresentation` exporting JPEG data); `.preferredColorScheme(.dark)` for automatic toolbar tinting
- **`ContentView.swift`** — Restructured to use `@State var selectedCatalogue` + `List(selection:)` with an explicit `NavigationStack` in the detail closure, fixing a NavigationSplitView "no next column" error when pushing item detail

#### Key Features:
- ✅ Photo carousel with page dots and tap-to-expand
- ✅ Full-screen photo viewer with swipe-between-photos and share
- ✅ All field types displayed with colour-coded SF Symbol icons
- ✅ Empty fields skipped (only non-empty values shown)
- ✅ Notes section shown only when present
- ✅ Edit sheet pre-populates via existing `AddEditItemView(catalogue:item:)`
- ✅ Delete with `confirmationDialog` + automatic dismiss
- ✅ Wishlist/Owned toggle mutates `item.isWishlist` directly (SwiftData auto-saves)
- ✅ Share text includes item name, all field values, and notes
- ✅ Cross-platform toolbar placements (iOS `.topBarTrailing`/`.topBarLeading` vs macOS `.primaryAction`)
- ✅ NavigationSplitView detail column correctly uses `NavigationStack` to enable push navigation

#### Files Created/Modified:
- `ItemDetailView.swift` (new)
- `PhotoCarouselView.swift` (new)
- `FullScreenPhotoView.swift` (new)
- `ContentView.swift` (restructured detail column)

---

### ✅ Phase 6: Polish & Platform Optimization (COMPLETE)
**Status:** ✅ Done

#### What's Built:

**Search:**
- `.searchable(text:)` on `CatalogueDetailView` — real-time filtering across item names and all field values
- Empty search results show `ContentUnavailableView.search` (distinct from "no items" empty state)

**Sort:**
- Sort by Date Added, Name, or any custom field (type-aware comparisons)
- Ascending/descending direction
- Both selections persisted via `@AppStorage("itemSortField")` / `@AppStorage("itemSortDirection")`
- nil-last logic for items missing a value for the sorted field
- First text field excluded from the custom field list (already covered by built-in "Name" sort)

**CSV Export:**
- `CatalogueExporter.csvString(for:)` — columns: Tab, Name, custom fields (by sortOrder), Notes, Photo Count
- Locale-invariant number formatting; proper CSV escaping (quotes, commas, newlines)
- `CatalogueCSVFile: Transferable` exposed via `ShareLink` in the toolbar

**Statistics:**
- `CatalogueStatsView` sheet — item counts (Total, Owned, Wishlist, Photos) and per-field completion %
- Completion rate shown in green at 100%, secondary colour otherwise

**Keyboard Shortcuts:**
- Cmd+N opens Add Item sheet (`.keyboardShortcut("n", modifiers: .command)`)

**Toolbar Reorganisation:**
- iOS: "…" leading menu (Edit Catalogue, Statistics, Export CSV); sort/layout/add trailing
- macOS: all items as `.primaryAction`

#### Files Created/Modified:
- `ItemSortOrder.swift` (new) — `ItemSortField` and `ItemSortDirection` enums
- `CatalogueExporter.swift` (new) — CSV generation + `CatalogueCSVFile: Transferable`
- `CatalogueStatsView.swift` (new) — statistics sheet
- `CatalogueDetailView.swift` (updated) — search, sort, export, stats, toolbar, empty state, Cmd+N

#### Deferred to future phases:
- Widgets, charts, tags/categories, duplicate detection, bulk edit, advanced filtering, print support

---

## 🏗️ Architecture Notes

### Data Model Relationships:
```
Catalogue
  ├─ FieldDefinitions (1:many, cascade delete)
  └─ CatalogueItems (1:many, cascade delete)
      ├─ FieldValues (1:many, cascade delete)
      └─ ItemPhotos (1:many, cascade delete)
```

### Key Design Decisions:
1. **Denormalized Field Values**: Each `FieldValue` stores the field name and type, not just a reference. This prevents data loss if field definitions change.

2. **Wishlist Flag**: Items use `isWishlist` boolean rather than separate models. Easy to move items between states.

3. **Photo Storage**: Photos stored as `Data` in SwiftData/iCloud. Simpler than file system management.

4. **Field Type Storage**: Each field type has its own property (`textValue`, `numberValue`, etc.). Only one is used based on `fieldType`.

5. **Sort Order**: All ordered collections use explicit `sortOrder` integer for user-defined ordering.

---

## 🐛 Known Issues / Tech Debt

### Current Issues:
- None known at this time

### Future Considerations:
1. **Field Definition Changes**: Current edit flow deletes and recreates field definitions. Need smarter migration that preserves existing field values.

2. **Photo Compression**: ✅ Implemented — `compressedAsJPEG(quality: 0.8)` applied on photo import.

3. **Performance**: For large catalogues (1000+ items), may need pagination or virtualization.

4. **Sync Conflicts**: Need to test iCloud sync conflict resolution.

5. **Undo/Redo**: Consider adding undo support for item edits.

---

## 📱 Platform Support

### Target Platforms:
- ✅ iOS 26.0+
- ✅ iPadOS 26.0+
- ✅ macOS 26.0+

### Testing Matrix:
- [ ] iPhone (various sizes)
- [ ] iPad (landscape/portrait)
- [ ] Mac (window resizing)
- [ ] iCloud sync between devices
- [ ] Accessibility (VoiceOver, Dynamic Type)
- [ ] Dark mode

---

## 🎨 Design Guidelines

### Colors:
- User-selected catalogue colors
- System accent color for UI elements
- Color-coded field types:
  - Blue: Text
  - Green: Number
  - Orange: Date
  - Purple: Boolean

### Icons:
- SF Symbols throughout
- User-selected catalogue icons
- 80+ curated icons in icon picker

### Layout:
- List and grid options for items
- Responsive to screen size
- NavigationSplitView for Mac/iPad

---

## 🧪 Testing Strategy

### Unit Tests Needed:
- [ ] `FieldValue` type-safe storage
- [ ] `Catalogue` computed properties
- [ ] Color hex conversion
- [ ] Field type validation

### UI Tests Needed:
- [ ] Create catalogue flow
- [ ] Add item flow
- [ ] Edit item flow
- [ ] Delete with cascade
- [ ] Photo management

### Manual Testing:
- [ ] iCloud sync
- [ ] Multi-device testing
- [ ] Data migration
- [ ] Performance with large datasets

---

## 📚 Resources & References

### Apple Documentation:
- SwiftData: https://developer.apple.com/documentation/swiftdata
- SwiftUI: https://developer.apple.com/documentation/swiftui
- PhotosUI: https://developer.apple.com/documentation/photosui

### App Architecture:
- MVVM pattern with SwiftUI
- SwiftData for persistence
- Async/await for concurrency

---

## 🎯 Success Criteria

### MVP (Minimum Viable Product):
- ✅ Create catalogues with custom fields
- ✅ Edit catalogues
- ✅ Add items with field values
- ✅ Add photos to items
- ✅ View items in grid/list
- ✅ View item detail with photos and field values
- ✅ Mark items as wishlist
- ⏸️ iCloud sync working

### Version 1.0:
- All MVP features
- ✅ Search items by name and field values
- ✅ Sort by any field (persisted)
- ✅ Basic statistics (counts + field completion)
- ✅ Export to CSV via share sheet

### Future Versions:
- Advanced filtering
- Charts and graphs
- Widgets
- Sharing/collaboration
- Mac-specific features

---

## 📝 Development Log

### February 20, 2026:
- ✅ Created SwiftData models with all relationships
- ✅ Set up model container with iCloud support
- ✅ Built catalogue list view with empty state
- ✅ Implemented add/edit catalogue sheet
- ✅ Created icon picker with 80+ icons
- ✅ Added field definition editor
- ✅ Made all code cross-platform (iOS/Mac)
- ✅ Fixed all build errors

### March 11, 2026:
- ✅ Built CatalogueDetailView with Owned/Wishlist tabs and grid/list toggle
- ✅ Implemented ItemCardView (grid layout) with photo thumbnails
- ✅ Implemented ItemRowView (list layout) with field summaries
- ✅ Simplified ContentView to navigate directly to CatalogueDetailView
- ✅ Layout preference persisted via @AppStorage
- ✅ Cross-platform image handling (iOS + macOS)
- ✅ Placeholder navigation for Phase 4 and Phase 5

### March 15, 2026:
- ✅ Built AddEditItemView with dynamic form driven by field definitions
- ✅ Implemented FieldInputView — per-type controls with platform-specific keyboard/autocapitalisation
- ✅ Implemented PhotoPickerView — PhotosPicker, thumbnail strip, captions, JPEG compression, sortOrder renumbering
- ✅ Added FieldValueDraft and PhotoDraft structs to FieldDefinitionDraft.swift
- ✅ Added compressedAsJPEG(quality:) to ImageHelpers.swift
- ✅ Wired CatalogueDetailView "+" button to AddEditItemView with defaultIsWishlist support

### March 15, 2026 (Phase 5):
- ✅ Built ItemDetailView with field display, notes, and full toolbar (edit/share/delete/move)
- ✅ Built PhotoCarouselView — paged TabView with caption overlay, tap-to-expand
- ✅ Built FullScreenPhotoView — full-screen paged viewer, per-photo share via PhotoTransferable
- ✅ Restructured ContentView detail column to use NavigationStack, fixing NavigationSplitView push navigation

### March 15, 2026 (Phase 6):
- ✅ Implemented real-time search via `.searchable` across item names and field values
- ✅ Added type-aware sort (Date Added, Name, any custom field) with ascending/descending, persisted via @AppStorage
- ✅ Built CatalogueExporter with locale-invariant CSV generation and proper escaping
- ✅ Exposed CSV export as ShareLink via CatalogueCSVFile: Transferable
- ✅ Built CatalogueStatsView — item counts and per-field completion rates
- ✅ Reorganised toolbar (iOS: "…" menu for secondary actions; macOS: all primary)
- ✅ Added Cmd+N keyboard shortcut for Add Item
- ✅ Fixed duplicate sort option — first text field excluded from custom field list (covered by built-in "Name")

---

## 💡 Ideas for Future Consideration

- **Barcode Scanning**: Use camera to scan item barcodes
- **Value Tracking**: Track item value over time for collectibles
- **Loan Tracking**: Mark items as loaned out and to whom
- **Condition Rating**: Visual condition assessment
- **Location Tracking**: Where items are stored
- **Multi-language**: Localization support
- **Themes**: Custom color themes
- **Templates**: Pre-made catalogue templates (stamps, coins, etc.)
- **Social Features**: Share catalogues with others
- **Marketplace Integration**: Check current market values

---

## 🤝 Contribution Guidelines

This is a personal project, but future considerations:
- Code style: Swift standard conventions
- Commit messages: Descriptive and concise
- Branch strategy: Feature branches
- Testing: All new features should have tests

---

**End of Plan Document**

*This document should be updated as development progresses.*
