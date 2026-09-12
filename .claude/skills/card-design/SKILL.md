---
name: card-design
description: Rules for cards and nested rounded shapes in this app — thumbnails and icon tiles inside cards, cards inside sections, photos in frames. Use whenever adding or adjusting a rounded view that sits inside another rounded view, or when a nested corner "looks off".
---

# Card design: nested corner radii

## The rule

When a rounded view sits inside another rounded view, the inner radius is **derived from the
outer one**, never picked by eye:

```
inner radius = outer radius − padding
```

Both curves then share a centre, so the gap between them is the same width all the way round
the corner. Any other value is visible:

- **Inner too large** (including "same radius as the parent", the usual mistake): the gap widens
  at the corners, so the child looks pinched inward at each corner.
- **Inner too small**: the gap narrows at the corners and the child looks boxy against the card.

## Corollaries

1. **Pad uniformly.** The inset must be the same on all four sides. With different horizontal
   and vertical padding the corners cannot be concentric whatever radius is chosen. If the row
   height or width needs to change, change the child's size, not one axis of the padding.
2. **Clamp near zero.** When padding ≥ outer radius the formula gives 0 or negative. Use a
   small radius (2–4pt) rather than a hard square — it reads as intentional.
3. **Match the curve style.** Use `style: .continuous` on both shapes; a continuous outer and a
   circular inner (or vice versa) diverge even when the radii are right.
4. **Chains compose.** For three levels (section → card → thumbnail) apply the formula at each
   step: `card = section − sectionPadding`, then `thumb = card − cardPadding`.

## How it is encoded here

Radii live in `AppConstants` as `outer − padding`, so the relationship survives later tweaks
to either number. Follow the same pattern for anything new:

```swift
enum ItemCard {
    static let contentPadding: CGFloat = 10
    static let thumbnailCornerRadius: CGFloat = CornerRadius.card - contentPadding   // 8
}
enum CatalogueCard {
    static let contentPadding: CGFloat = 14
    static let iconTileCornerRadius: CGFloat = CornerRadius.card - contentPadding    // 4
}
```

- `CornerRadius.card` (18) is the outer radius for list cards on both the Catalogues and item
  screens (`CatalogueCardView`, `ItemCardModifier`).
- `ItemRowView` clips the thumbnail with `ItemCard.thumbnailCornerRadius`; the placeholder
  inside it is a plain `Rectangle` because the clip already supplies the corners.
- `CatalogueCardView.iconTile` uses `CatalogueCard.iconTileCornerRadius`.

## Checking it

Numbers in code are not proof. Build to the simulator, screenshot the screen, and crop in on a
corner (`sips -c <h> <w> --cropOffset <y> <x>`) — an uneven gap is obvious at 3× and invisible
in a full-screen view. In this project the layouts that matter are the Catalogues list and a
catalogue's **list** (not gallery) layout.

Reference: https://blog.92learns.com/border-radius-rules/
