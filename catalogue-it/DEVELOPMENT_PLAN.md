# Catalogue-It Development Plan

**App Overview:** A multi-platform catalogue app that lets users create custom catalogues with flexible field definitions, photos, and wishlist support. Built with SwiftUI and SwiftData with iCloud sync.

**Created:** February 20, 2026  
**Last Updated:** February 20, 2026

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

### 📌 Phase 3: Catalogue Detail Screen (NEXT)
**Status:** 🔜 Not Started

#### What to Build:
1. **CatalogueDetailView** - Replace `CatalogueDetailPlaceholder`
   - Tabs for "Owned" and "Wishlist"
   - Toggle between grid and list layout
   - Display items with primary photo thumbnails
   - Show key field values (e.g., name, year)
   - Empty state when no items exist
   - Add item button

2. **Item Card Components**:
   - Grid card view (photo + name)
   - List row view (photo + multiple fields)
   - Tap to view item detail

#### Technical Notes:
- Use `@Query` to fetch items from catalogue
- Filter by `isWishlist` for tabs
- Store layout preference in `@AppStorage`
- Use `AsyncImage` or custom image view for photos
- Consider lazy loading for performance

#### Estimated Complexity: Medium
#### Files to Create:
- `CatalogueDetailView.swift`
- `ItemCardView.swift` (grid)
- `ItemRowView.swift` (list)

---

### 📌 Phase 4: Add/Edit Items (PLANNED)
**Status:** ⏸️ Not Started

#### What to Build:
1. **AddEditItemView**:
   - Dynamic form based on catalogue's field definitions
   - Input components for each field type:
     - Text: TextField
     - Number: TextField with number keyboard
     - Date: DatePicker
     - Boolean: Toggle
   - Photo picker (multiple photos)
   - Photo management (reorder, delete, add captions)
   - Wishlist toggle
   - Notes field

2. **Photo Management**:
   - `PhotosPicker` for selecting images
   - Convert to Data for SwiftData storage
   - Thumbnail generation
   - Sortable photo grid

#### Technical Notes:
- Use `PhotosUI` framework for photo picking
- Compress images before storing
- Validate required fields
- Auto-save or manual save?
- Consider photo size limits

#### Estimated Complexity: High
#### Files to Create:
- `AddEditItemView.swift`
- `PhotoPickerView.swift`
- `FieldInputView.swift` (reusable field input component)

---

### 📌 Phase 5: Item Detail Screen (PLANNED)
**Status:** ⏸️ Not Started

#### What to Build:
1. **ItemDetailView**:
   - Photo carousel/gallery
   - All field values displayed
   - Notes section
   - Edit button → opens AddEditItemView
   - Delete button with confirmation
   - Move to wishlist/owned button
   - Share functionality

2. **Photo Viewer**:
   - Full-screen photo viewing
   - Swipe between photos
   - Show captions
   - Share photo

#### Technical Notes:
- Use `TabView` with `PageTabViewStyle` for photo carousel
- Formatting for each field type
- Confirmation dialog for destructive actions

#### Estimated Complexity: Medium
#### Files to Create:
- `ItemDetailView.swift`
- `PhotoCarouselView.swift`
- `FullScreenPhotoView.swift`

---

### 📌 Phase 6: Polish & Platform Optimization (PLANNED)
**Status:** ⏸️ Not Started

#### What to Add:

**Search & Filter:**
- Search items by field values
- Filter by field criteria
- Saved searches/filters

**Sorting:**
- Sort by any field
- Multiple sort criteria
- Save sort preferences

**Platform-Specific:**
- iPad: Optimized layouts, drag & drop
- Mac: Menu bar commands, keyboard shortcuts, toolbar customization
- Widgets: Show catalogue summaries on home screen

**Export/Sharing:**
- Export catalogue to CSV/JSON
- Share items
- Print support
- Backup/restore

**Advanced Features:**
- Statistics view (total value, count by type, etc.)
- Charts and graphs
- Tags/categories across catalogues
- Duplicate item detection
- Bulk edit

#### Estimated Complexity: High
#### Multiple files to create

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

2. **Photo Compression**: Need to implement image compression before storage to prevent database bloat.

3. **Performance**: For large catalogues (1000+ items), may need pagination or virtualization.

4. **Sync Conflicts**: Need to test iCloud sync conflict resolution.

5. **Undo/Redo**: Consider adding undo support for item edits.

---

## 📱 Platform Support

### Target Platforms:
- ✅ iOS 17.0+
- ✅ iPadOS 17.0+
- ✅ macOS 14.0+

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
- ⏸️ Add items with field values
- ⏸️ Add photos to items
- ⏸️ View items in grid/list
- ⏸️ Mark items as wishlist
- ⏸️ iCloud sync working

### Version 1.0:
- All MVP features
- Search and filter
- Basic statistics
- Export functionality

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

**Next Session:** Begin Phase 3 - Catalogue Detail Screen

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
