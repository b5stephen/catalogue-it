# Catalogue-It

A multi-platform SwiftUI app for managing personal collections. Create custom catalogues for anything — model planes, stamps, books, vinyl records — with flexible fields, photo attachments, and automatic iCloud sync across all your Apple devices.

## Features

- **Custom catalogues** — name, icon, and color per collection
- **Flexible field types** — Text, Number, Date, and Boolean fields
- **Wishlist tracking** — mark items as owned or wishlist
- **Photo attachments** — add multiple photos with captions per item
- **iCloud sync** — data syncs automatically across iPhone, iPad, and Mac
- **Drag-to-reorder** — reorder field definitions within a catalogue
- **Cross-platform** — native UI for iOS, iPadOS, and macOS

## Requirements

- Xcode 15+
- iOS 17+ / iPadOS 17+ / macOS 14+
- An Apple Developer account (for iCloud entitlements)

## Getting Started

```bash
# Clone the repository
git clone https://github.com/b5stephen/catalogue-it.git
cd catalogue-it

# Open in Xcode
open catalogue-it.xcodeproj
```

Select your target device or simulator, then press **Cmd+R** to build and run. No external dependencies or package installs are required.

## Project Structure

```
catalogue-it/
├── catalogue_itApp.swift       # App entry point, SwiftData ModelContainer setup
├── ContentView.swift           # Home screen with catalogue list
├── AddEditCatalogueView.swift  # Catalogue creation/editing UI
├── Item.swift                  # All SwiftData models
├── DEVELOPMENT_PLAN.md         # Phased feature roadmap
└── Assets.xcassets/            # App icons and color assets
catalogue-it.xcodeproj/         # Xcode project configuration
```

## Data Model

```
Catalogue
  ├─ FieldDefinitions (1:many, cascade delete)
  └─ CatalogueItems (1:many, cascade delete)
      ├─ FieldValues (1:many, cascade delete)
      └─ ItemPhotos (1:many, cascade delete)
```

## Building from the Command Line

```bash
# Debug build
xcodebuild -project catalogue-it.xcodeproj -scheme catalogue-it -configuration Debug build

# Type-check only (fast feedback)
swiftc -typecheck catalogue-it/*.swift
```

## Development Status

See [DEVELOPMENT_PLAN.md](catalogue-it/DEVELOPMENT_PLAN.md) for the full roadmap.

**Complete:**
- Core SwiftData models with iCloud sync
- Catalogue list with empty state
- Add/edit catalogue sheet (name, icon, color)
- Field definition editor with drag-to-reorder

**Planned:**
- Catalogue detail screen and item cards
- Add/edit items with dynamic field forms
- Photo picking and management
- Search, filter, and sort
- Export and sharing

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift |
| UI | SwiftUI |
| Persistence | SwiftData |
| Sync | iCloud (CloudKit via SwiftData) |
| Dependencies | None (Apple frameworks only) |

## License

This project is not yet licensed. All rights reserved.
