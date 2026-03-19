# Catalogue-It Development Context

## Architectural Decisions

### SwiftData Performance Optimization (March 2026)
- **What:** Refactored `Catalogue` and `CatalogueItem` models to remove computed properties that filtered relationships (`ownedItems`, `wishlistItems`, `primaryPhoto`). Introduced `CatalogueItemsView` which utilizes `@Query` with dynamic predicates.
- **Why:** Accessing relationship-filtering computed properties in SwiftData (e.g., `items.filter { ... }`) forces the entire relationship array to load into memory. In large collections, this causes severe UI lag and high memory pressure. Using `@Query` allows the database to handle filtering efficiently at the persistence layer.
- **Impact:** Improved sidebar loading speed and reduced memory footprint when browsing large catalogues.
- **Future Considerations:** If item counts (Owned/Wishlist) are required in the sidebar again, consider implementing denormalized counters on the `Catalogue` model that update when items are added/removed, rather than re-calculating from the relationship.

## Project Structure
- **Models/**: SwiftData `@Model` definitions.
- **Catalogues/**: Views related to catalogue management and the main list.
- **Items/**: Views for individual item details, grids, and rows.
- **Fields/**: Custom field definition and input views.
- **Utilities/**: Shared helpers for colors, images, and data export.
