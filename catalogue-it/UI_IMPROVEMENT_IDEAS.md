# UI Improvement Ideas

Research date: 2026-03-29

Inspired by UI/UX patterns from: Things 3, Notion, Craft, Bear, Obsidian, Agenda, GoodNotes, Fantastical, Readwise Reader, Linear.

---

## Current State

The app has a solid foundation:
- `NavigationSplitView` sidebar → catalogue detail → item detail
- Grid/List toggle, segmented tabs (All/Owned/Wishlist), sort menu
- Form-based editing, photo carousel, drag-to-reorder
- Soft deletion with recovery

---

## Suggested UI Changes

### 1. Richer Empty States (Things 3, Notion)

**Current:** Generic `ContentUnavailableView` with system defaults.

**Suggestion:** Create custom empty state views with personality and guidance:
- First-launch: Show a pre-populated sample catalogue (e.g., "My Books") so users immediately understand the app
- Catalogue empty state: Illustration + "Add your first [item type]" button inline (not just a toolbar button)
- Search no-results: Offer "Create item named X" shortcut

**File:** `CatalogueEmptyStateView.swift` — extend with `isFirstCatalogue` context and a "Try a sample" CTA.

---

### 2. Filter Chips Below Search Bar (Bear, Linear)

**Current:** Tab picker (All/Owned/Wishlist) is the only filter; sort is buried in a menu.

**Suggestion:** Replace the segmented `TabView` picker with inline filter chips that can be combined:
```
[All] [Owned ✓] [Wishlist] | [Sorted: Name ↑]
```
Chips are horizontally scrollable, tappable to toggle, with a subtle fill when active. This pattern (from Bear's tag system + Linear's filter chips) reduces cognitive load and supports future filter types (by field value, date range, etc.).

**Files:** `CatalogueDetailView.swift`, new `FilterChipsView.swift`

---

### 3. Item Card Improvements (Fantastical, Things 3)

**Current:** `ItemCardView` has a photo + 2-line title + optional heart badge. `ItemRowView` shows thumbnail + title + 2 field summaries.

**Suggestions:**
- **Card view:** Add a color accent strip at the top matching the catalogue's color — gives instant visual grouping and personality
- **Row view:** Show a colored dot or icon (from `FieldType.color`) next to the first field summary — helps distinguish text vs number vs date values at a glance
- **Wishlist badge:** Move the heart from an overlay to a dedicated badge row at the bottom of the card (less cluttered)
- **Primary field pill:** If the first field has a value, show it as a small rounded pill below the photo (Fantastical "event pill" pattern)

**Files:** `ItemCardView.swift`, `ItemRowView.swift`

---

### 4. Context Menus on Item Rows/Cards (Things 3, Notion)

**Current:** No long-press context menu on items in the grid or list.

**Suggestion:** Add `.contextMenu` with:
- Duplicate Item
- Move to Wishlist / Mark as Owned
- Share
- Delete (with destructive role)

This matches the iOS system pattern and lets users act on items without opening the detail view.

**Files:** `ItemCardView.swift`, `ItemRowView.swift`

---

### 5. Item Detail — Grouped Field Sections (Craft, Notion)

**Current:** `ItemFieldsSection` renders all fields as a flat list of `FieldRowView` dividers.

**Suggestion:** Group fields visually by type with subtle section headers:
- **Text fields** first (primary info)
- **Dates** grouped together
- **Numbers** grouped together
- **Booleans** at the bottom as toggles

Additionally, add a "completion ring" or progress bar at the top of the detail view showing what % of fields are filled — `CatalogueStatsView` already computes per-field completion rates; surface this per-item.

**Files:** `ItemDetailSections.swift`, `ItemDetailView.swift`

---

### 6. Photo Carousel — Swipe-to-Dismiss + Pinch-to-Zoom (GoodNotes, Readwise)

**Current:** `FullScreenPhotoView` uses a `TabView` with black background. No zoom or dismissal gesture.

**Suggestion:**
- Add `MagnificationGesture` for pinch-to-zoom (using `.scaleEffect` + `@GestureState`)
- Add `DragGesture` for swipe-down-to-dismiss (matching iOS Photos behavior)
- Show photo count as "2 / 5" overlay rather than system page indicators

**File:** `FullScreenPhotoView.swift`

---

### 7. Catalogue Row — Quick Stats Pill (Fantastical, Agenda)

**Current:** `CatalogueRow` shows icon + name + item count (as a caption).

**Suggestion:** Show a compact stats breakdown inline:
```
[📦 Model Planes]   [12 owned · 3 wishlist]
```
Replace the plain count with owned/wishlist breakdown. Uses existing `Item` count queries.

**File:** `CatalogueRow.swift`

---

### 8. Home Screen Quick Actions (Things 3)

**Suggestion:** Add `UIApplicationShortcutItem` entries in `catalogue_itApp.swift`:
- "Add Item" (opens directly to add sheet)
- "Search" (opens with search bar focused)
- "Recently Deleted" (direct recovery access)

**File:** `catalogue_itApp.swift`

---

### 9. Keyboard Shortcuts — Power User Layer (Linear)

**Current:** Only `Cmd+N` for add item.

**Suggestion:** Add:
- `Cmd+F` — focus search
- `Cmd+1/2/3` — switch tabs (All/Owned/Wishlist)
- `Cmd+G` / `Cmd+L` — toggle Grid/List
- `Cmd+Backspace` — delete selected item

**Files:** `CatalogueDetailView.swift`, `ItemDetailView.swift`

---

### 10. Inline Sort Indicator (Notion, Linear)

**Current:** Sort is only visible inside the `SortMenuButton` menu.

**Suggestion:** Show the active sort as a small label next to the item count:
```
24 items  ·  A→Z
```
Tapping this text opens the sort menu directly — more discoverable than a toolbar button.

**File:** `CatalogueDetailView.swift`

---

## Priority Order

| Priority | Change | Effort |
|----------|--------|--------|
| High | Filter chips (replaces tab picker) | Medium |
| High | Context menus on items | Low |
| High | Richer empty states with sample data | Medium |
| Medium | Card color accent strip | Low |
| Medium | Item detail field grouping | Low |
| Medium | Inline sort indicator | Low |
| Medium | Catalogue row stats pill | Low |
| Low | Pinch-to-zoom in photo viewer | Medium |
| Low | Swipe-to-dismiss photo viewer | Medium |
| Low | Keyboard shortcuts | Low |
| Low | Home screen quick actions | Medium |

---

## Reference: Top iOS Productivity App Patterns

### Things 3
- Detail-hiding pattern: show key info at a glance, expand for metadata
- Gray text for secondary properties
- Glassy/Liquid Glass buttons (iOS 26 design language)
- Quick Find as primary navigation

### Notion
- 8px grid system for consistent spacing
- Drag handles signaling customizable elements
- Generous spacing that signals importance
- Thumb-friendly 44×44pt tap targets

### Bear
- Tag-based organization with nested hierarchy
- Accent color splashed purposefully throughout UI
- Customizable typography
- Small delightful animations

### Fantastical / Agenda
- Color-coded pill/badge pattern for items
- Dual-view: overview + detail simultaneously
- Swipe gestures for navigation between views

### Readwise Reader
- Semantic color usage (colors carry meaning)
- Minimal distractions — hide complexity until needed
- Double-tap gestures for quick actions

### Linear
- Reduced visual noise design
- Opinionated workflow reduces decision fatigue
- Keyboard-first navigation for power users
- Command palette for actions

### GoodNotes
- Mode-switching toolbar (context-aware actions)
- Toolbar positioned directly under nav bar
- Scribble / Apple Pencil integration patterns
