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
UITest/                            # All UI Tests live here
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

Configured in `catalogue_itApp.swift` via `ModelConfiguration(isStoredInMemoryOnly: false)`. SwiftData handles conflict resolution automatically.
