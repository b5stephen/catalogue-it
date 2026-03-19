# Catalogue-It

A multi-platform SwiftUI collection management app for iOS, iPadOS, and macOS. Users can create custom catalogues (e.g., model planes, stamps, books) with flexible field definitions, photo attachments, and iCloud sync.

## Tech Stack

- **Language:** Swift 6
- **UI:** SwiftUI
- **Persistence:** SwiftData (with iCloud sync)
- **Platform targets:** iOS 26+, iPadOS 26+, macOS 26+
- **No external dependencies** — all frameworks are Apple built-ins

## Project Structure

All files must be placed in the catalogue-it subfolder. Never place files in the Xcode project root group. Follow a feature-based subdirectories structure like below

```
catalogue-it/
├── catalogue_itApp.swift          # App entry point, SwiftData ModelContainer setup
├── DEVELOPMENT_PLAN.md            # Phased feature roadmap
├── Localizable.xcstrings          # Localization strings
├── Assets.xcassets/               # App resources (icons, colors)
├── Catalogues/                    # Catalogue list and detail views
├── Fields/                        # Field definition UI
├── Items/                         # Item management and display views
├── Models/                        # SwiftData model definitions
├── Photos/                        # Photo management views
├── Types/                         # Supporting enums and value types
└── Utilities/                     # Shared helpers and extensions
catalogue-it.xcodeproj/            # Xcode project configuration
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

See `DEVELOPMENT_PLAN.md` for the full phased roadmap. As of March 2026:

- **Complete:** Data models, catalogue list view, add/edit catalogue sheet, icon picker, field definition editor with drag-to-reorder, catalogue detail screen (grid + list item browser), item management, photo picking, code review refactor (feature-based subdirectories, Swift 6 best practices)
- **Planned:** Search/filter/sort, export/sharing
