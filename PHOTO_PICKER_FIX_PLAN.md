# Fix: Photo Delete & Preview — Switch Edit Mode to Standard List

## Context

Commit `f21959a` ("Redesign photo picker UI with edit-mode pattern") introduced an
"Edit/Done" mode for the photo grid in `PhotoPickerView`. Two new interaction paths
are broken in both Add and Edit catalogue item forms:

1. **X delete button** (visible only in edit mode) does nothing when tapped.
2. **Tapping a photo when not in edit mode** briefly shows the preview sheet, which
   then immediately dismisses itself.

Root cause: a parent-level reorder `DragGesture` competes with the Button (X)
and the inner `onTapGesture` (preview opener) inside every cell, causing gesture
arbitration to swallow taps.

Rather than patch the gesture stack, switch to the **standard SwiftUI list editing
pattern**. When edit mode is active, swap the `LazyVGrid` for a vertical
`ForEach` row layout that uses `.onMove` and `.onDelete`. SwiftUI handles the
drag handles, swipe-to-delete, and reorder animations natively — no custom
DragGesture, no matchedGeometryEffect, no overlay tricks.

Goal: photos display as a thumbnail grid by default; tapping a thumbnail opens
the existing `PhotoEditDetailSheet`; tapping **Edit** flips the section into a
standard reorder/delete list; tapping **Done** flips back.

## Approach

### Change 1 — `PhotoPickerView.body`, photo section content

Replace the unconditional `PhotoGridView` call with a branch on `isEditingPhotos`:

```swift
Section {
    if isEditingPhotos {
        ForEach($photos) { $photo in
            PhotoListRow(photo: $photo)
        }
        .onMove { from, to in
            photos.move(fromOffsets: from, toOffset: to)
            for index in photos.indices { photos[index].priority = index }
        }
        .onDelete { offsets in
            offsets.forEach { pendingDeleteId = photos[$0].id }
        }
    } else {
        PhotoGridView(
            photos: $photos,
            onTap: { id in
                if let draft = photos.first(where: { $0.id == id }) {
                    previewDraft = draft
                }
            }
        )
    }

    PhotosPicker(...)        // unchanged
    #if os(iOS)
    Take Photo button         // unchanged
    #endif
}
```

### Change 2 — bind edit mode via the environment

Add to the Section (or its parent Form), so `.onMove` shows reorder handles and
`.onDelete` reveals red minus controls without requiring a swipe:

```swift
.environment(\.editMode, .constant(isEditingPhotos ? .active : .inactive))
```

This goes on the same scope where the other Section modifiers (sheet, alert,
confirmationDialog) currently live.

### Change 3 — simplify `PhotoGridView`

Strip the grid down to its read-only role:

- Remove `isEditing`, `onDelete`, `onMove` parameters and the custom
  `DragGesture` / `reorderGesture(for:)` / `swapIfNeeded(id:)` / `liftedPhotoOverlay`
  / `cellFrames` / `draggingId` / `dragPosition` / `gridNamespace` state.
- Keep just the `LazyVGrid` with `PhotoThumbnailView` cells. Each cell has the
  existing `.contentShape(.rect).onTapGesture { onTap(photo.id) }`.

### Change 4 — simplify `PhotoThumbnailView`

- Remove `isEditing` and `onDelete` parameters and the overlay X button entirely.
  The thumbnail is now purely a display + tap target.

### Change 5 — new tiny `PhotoListRow` view

Sibling to `PhotoThumbnailView`, used only in edit mode. Renders one row inside
the Form section:

```swift
private struct PhotoListRow: View {
    @Binding var photo: PhotoDraft

    var body: some View {
        HStack(spacing: 12) {
            if let image = photo.imageData.asImage() {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.small))
            }
            Text(photo.caption.isEmpty ? "No caption" : photo.caption)
                .foregroundStyle(photo.caption.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
        }
    }
}
```

Captions remain read-only here per design — they are edited in
`PhotoEditDetailSheet`, which is still reachable by tapping a thumbnail when
**not** in edit mode. (No tap target on edit-mode rows; the system handles
drag/delete affordances.)

### Change 6 — `.onDelete` and confirmation flow

`.onDelete` provides the IndexSet of rows the user swiped/minus-tapped.
Forward the first id to the existing `pendingDeleteId` flow so the confirmation
dialog remains the single source of truth for destructive confirmation. The
existing `deletePhoto(id:)` helper already reassigns `priority` after removal.

### Change 7 — `.onMove` reorder logic

Inline `photos.move(fromOffsets:toOffset:)` plus priority renumber, mirroring
`movePhoto(fromId:toId:)`. The old `movePhoto` helper can be deleted along with
the grid drag code since nothing else calls it.

### Cleanup

After the above, the following can be deleted from `PhotoPickerView.swift`:
- `CellFramePreference` PreferenceKey
- `movePhoto(fromId:toId:)` helper

Net effect: PhotoPickerView.swift shrinks by ~80 lines and contains no custom
gesture code.

## Critical files

- `catalogue-it/Photos/PhotoPickerView.swift` — only file modified.
  - `PhotoPickerView.body` — branch the section content on `isEditingPhotos`;
    attach `.environment(\.editMode, ...)`.
  - `PhotoGridView` — strip to display-only.
  - `PhotoThumbnailView` — drop edit/delete parameters and X overlay.
  - Add `PhotoListRow`.
  - Delete `CellFramePreference`, `movePhoto`, and reorder gesture code.

No call site changes — `AddEditItemView` keeps `PhotoPickerView(photos: $photoDrafts)`.

## Verification

1. Build via `mcp__xcode__BuildProject` (or `xcodebuild -project catalogue-it.xcodeproj -scheme catalogue-it -configuration Debug build`).
2. Run on iOS simulator. Open a catalogue → **Add Item**.
3. Add ≥ 3 photos via the picker.
4. **Tap a thumbnail (not in edit mode)** → `PhotoEditDetailSheet` opens and stays open until Done/Delete; caption edits persist on return.
5. Tap **Edit** in the Photos section header → grid is replaced by vertical rows with reorder handles on the right and red minus indicators on the left (iOS).
6. **Drag a row by its handle** to a new position → list updates; tap Done → returned grid reflects the new order.
7. Tap a red minus / swipe a row → delete confirmation dialog appears → **Delete Photo** removes that photo; rows below shift up.
8. After deleting all photos, the Edit button disappears and the section returns to the picker-only state.
9. Repeat steps 4–7 in the **Edit Item** form to confirm both entry points behave identically.
10. macOS sanity check (best effort): list still renders; delete via red minus works even without swipe gesture.
