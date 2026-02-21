# Catalogue-It

A multi-platform SwiftUI collection management app for iOS, iPadOS, and macOS. Users can create custom catalogues (e.g., model planes, stamps, books) with flexible field definitions, photo attachments, and iCloud sync.

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI
- **Persistence:** SwiftData (with iCloud sync)
- **Platform targets:** iOS 17+, iPadOS 17+, macOS 14+
- **No external dependencies** — all frameworks are Apple built-ins

## Project Structure

```
catalogue-it/
├── catalogue_itApp.swift       # App entry point, SwiftData ModelContainer setup
├── ContentView.swift           # Home screen with catalogue list
├── AddEditCatalogueView.swift  # Catalogue creation/editing UI
├── Item.swift                  # All SwiftData models
├── DEVELOPMENT_PLAN.md         # Phased feature roadmap
└── Assets.xcassets/            # App resources
catalogue-it.xcodeproj/         # Xcode project configuration
```

## Data Models (`Item.swift`)

| Model | Purpose |
|-------|---------|
| `Catalogue` | Collection container with name, icon, color |
| `FieldDefinition` | Custom field schema (Text, Number, Date, Boolean) |
| `CatalogueItem` | Individual item in a catalogue |
| `FieldValue` | Typed value for a field on an item |
| `ItemPhoto` | Photo attachment with caption and sort order |

**Relationship tree:**
```
Catalogue
  ├─ FieldDefinitions (1:many, cascade delete)
  └─ CatalogueItems (1:many, cascade delete)
      ├─ FieldValues (1:many, cascade delete)
      └─ ItemPhotos (1:many, cascade delete)
```

**Key design decisions:**
- `FieldValue` denormalizes field name and type to prevent data loss if definitions change
- Photos stored as `Data` directly in SwiftData
- All ordered collections use an explicit `sortOrder: Int` field
- Items use an `isWishlist: Bool` flag rather than separate models

## Build & Run

```bash
# Open in Xcode
open catalogue-it.xcodeproj

# Command-line build
xcodebuild -project catalogue-it.xcodeproj -scheme catalogue-it -configuration Debug build

# Type-check only (fast)
swiftc -typecheck catalogue-it/*.swift
```

## Testing

No tests exist yet. Planned tests are documented in `DEVELOPMENT_PLAN.md`.

```bash
# Run tests when added
xcodebuild test -project catalogue-it.xcodeproj -scheme catalogue-it -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Linting

SwiftLint is not configured. The Swift compiler provides type checking.

```bash
# Optional: run SwiftLint if installed
swiftlint lint catalogue-it/
```

## Platform-Specific Code

The codebase uses conditional compilation for cross-platform support:

```swift
#if os(iOS)
// iOS/iPadOS-specific code
#elseif os(macOS)
// macOS-specific code
#endif
```

## iCloud Sync

Configured in `catalogue_itApp.swift` via `ModelConfiguration(isStoredInMemoryOnly: false)`. SwiftData handles conflict resolution automatically.

## Development Status

See `DEVELOPMENT_PLAN.md` for the full phased roadmap. As of Feb 2026:

- **Complete:** Data models, catalogue list view, add/edit catalogue sheet, icon picker, field definition editor with drag-to-reorder
- **Planned:** Catalogue detail screen, item management, photo picking, search/filter/sort, export/sharing
