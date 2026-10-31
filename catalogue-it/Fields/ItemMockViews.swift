//
//  ItemMockViews.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Mock Item Screens

/// Pieces shared by `FieldPreviewSection` and `CataloguePreviewView`. Placement mirrors
/// `ItemDetailView` (`FieldRowView`, `ViewFieldRowView`) and `ItemRowView` — keep it in step.
enum MockScreen {
    static let padding: CGFloat = 10
    /// Outer = card + padding, so the mock cards sit concentric in the screen (card-design skill).
    static let shape = RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card + padding, style: .continuous)
}

extension View {
    func mockScreen(tint: Color) -> some View {
        padding(MockScreen.padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(tint.opacity(0.08), in: MockScreen.shape)
            .overlay { MockScreen.shape.strokeBorder(.separator) }
            .tint(tint)
    }

    /// A `CatalogueSectionCard`-style card inside the mock screen.
    func mockCard(fill: CardFill) -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
    }

    /// Marks the field being edited among its placeholder neighbours. Rows and lines only: a
    /// chip or icon is already the only real value in its row, and a halo crowds it.
    func highlighted() -> some View {
        background {
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.small, style: .continuous)
                .fill(.tint.opacity(0.14))
                .padding(.horizontal, -6)
                .padding(.vertical, 2)
        }
    }
}

// MARK: - Placeholders

/// Lengths for the redacted placeholders; never shown as text.
enum PreviewSamples {
    static let title = "Sample item name"
    static let value = "Sample"
}

struct RedactedSample: View {
    var sample: String = PreviewSamples.value

    var body: some View {
        Text(verbatim: sample)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

struct MockEmptyValue: View {
    var body: some View {
        Text(verbatim: "—")
            .foregroundStyle(.tertiary)
    }
}

struct MockThumbnail: View {
    var body: some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Details Row

struct MockDetailRow<Value: View>: View {
    let label: String
    let layout: DetailLabelLayout
    @ViewBuilder let value: Value

    var body: some View {
        switch layout {
        case .beside:
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                value
            }
            .padding(.vertical, 10)
        case .above:
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                value
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - List Row

struct MockListRow<Thumbnail: View, Title: View, Lines: View, Trailing: View>: View {
    let showsThumbnail: Bool
    let fill: CardFill
    @ViewBuilder let thumbnail: Thumbnail
    @ViewBuilder let title: Title
    @ViewBuilder let lines: Lines
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if showsThumbnail {
                thumbnail
                    .frame(width: AppConstants.ThumbnailSize.list, height: AppConstants.ThumbnailSize.list)
                    .clipShape(.rect(cornerRadius: AppConstants.ItemCard.thumbnailCornerRadius, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.headline)
                    .lineLimit(1)
                lines
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minHeight: AppConstants.ThumbnailSize.list, alignment: .leading)
            Spacer(minLength: 0)
            trailing
        }
        .padding(AppConstants.ItemCard.contentPadding)
        .background(fill, in: .rect(cornerRadius: AppConstants.CornerRadius.card, style: .continuous))
    }
}

// MARK: - Details Caption

struct MockDetailsCaption: View {
    var body: some View {
        Text("Details")
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.tint)
            .padding(.leading, 4)
    }
}
