//
//  ItemShareCard.swift
//  catalogue-it
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - Card Shape

enum ItemShareCardShape: CaseIterable, Identifiable {
    case square
    case portrait
    case story

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .square: "Square"
        case .portrait: "Portrait"
        case .story: "Story"
        }
    }

    /// Points, which render at one pixel each.
    var size: CGSize {
        switch self {
        case .square: CGSize(width: 1080, height: 1080)
        case .portrait: CGSize(width: 1080, height: 1350)
        case .story: CGSize(width: 1080, height: 1920)
        }
    }

    fileprivate var photoHeight: CGFloat {
        switch self {
        case .square: 380
        case .portrait: 560
        case .story: 900
        }
    }
}

// MARK: - Item Share Card

/// Laid out in a fixed `shape.size` canvas and always light, so the preview (scaled down) and the
/// rendered PNG are the same view.
struct ItemShareCard: View {
    let title: String
    let status: String?
    let rows: [ItemShareText.Entry]
    let photo: CGImage?
    let shape: ItemShareCardShape
    let icon: CatalogueIcon
    let colorHex: String
    /// `nil` hides the name.
    let catalogueName: String?

    private enum Layout {
        static let margin: CGFloat = 56
        static let panelPadding: CGFloat = 24
        static let panelCornerRadius: CGFloat = 48
        /// Inner radius = outer − padding (card-design skill).
        static let photoCornerRadius = panelCornerRadius - panelPadding
        static let rowHeight: CGFloat = 52
        static let iconTile: CGFloat = 72
        static let iconTileCornerRadius: CGFloat = 20
    }

    private var palette: CataloguePalette {
        CataloguePalette(hex: colorHex, scheme: .light, isSelected: false)
    }

    var body: some View {
        VStack(spacing: 32) {
            panel
            footer
        }
        .padding(Layout.margin)
        .frame(width: shape.size.width, height: shape.size.height)
        .background(palette.fill)
        .environment(\.colorScheme, .light)
    }

    // MARK: Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 28) {
            photoArea
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.system(size: 64, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.primary)
                rowList
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(Layout.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: .rect(cornerRadius: Layout.panelCornerRadius, style: .continuous))
    }

    private var photoArea: some View {
        Color.clear
            .frame(height: shape.photoHeight)
            .overlay {
                if let photo {
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(palette.fill)
                        .overlay {
                            CatalogueIconView(icon: icon, color: palette.iconGlyph, size: 160)
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                if let status, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(palette.fillDeepStop)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.white, in: .capsule)
                        .padding(20)
                }
            }
            .clipShape(.rect(cornerRadius: Layout.photoCornerRadius, style: .continuous))
    }

    /// As many rows as fit; the remainder is counted rather than clipped mid-row.
    private var rowList: some View {
        GeometryReader { proxy in
            let capacity = max(Int(proxy.size.height / Layout.rowHeight), 0)
            let overflow = rows.count > capacity
            let shown = overflow ? max(capacity - 1, 0) : rows.count
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.prefix(shown).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(row.value)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    .font(.system(size: 34))
                    .frame(height: Layout.rowHeight)
                }
                if overflow && capacity > 0 {
                    Text("+\(rows.count - shown) more")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: Layout.rowHeight, alignment: .leading)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 20) {
            CatalogueIconView(
                icon: icon,
                color: palette.iconGlyph,
                size: 36,
                tileCornerRadius: Layout.iconTileCornerRadius
            )
            .frame(width: Layout.iconTile, height: Layout.iconTile)
            .background(palette.iconTint, in: .rect(cornerRadius: Layout.iconTileCornerRadius, style: .continuous))

            if let catalogueName {
                Text(catalogueName)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            Text(verbatim: "Catalogue-It")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.secondaryText)
        }
    }
}

// MARK: - Building

extension ItemShareCard {

    init(
        item: CatalogueItem,
        in catalogue: Catalogue,
        columns: Set<ExportColumn>,
        photo: CGImage?,
        shape: ItemShareCardShape,
        showsCatalogueName: Bool
    ) {
        self.init(
            title: ItemShareText.title(for: item, in: catalogue),
            status: catalogue.statusField.map { item.displayValue(for: $0) },
            rows: ItemShareText.entries(for: item, in: catalogue, columns: columns, leaveOutBlanks: true),
            photo: photo,
            shape: shape,
            icon: catalogue.icon,
            colorHex: catalogue.colorHex,
            catalogueName: showsCatalogueName ? catalogue.name : nil
        )
    }

    /// Fits the photo area at its largest, so a 48-megapixel original isn't held for the render.
    nonisolated static func downsample(_ data: Data) -> CGImage? {
        guard let thumbnail = makeThumbnailData(from: data, maxDimension: 1600),
              let source = CGImageSourceCreateWithData(thumbnail as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - Renderer

@MainActor
enum ItemShareCardRenderer {

    static func pngData(for card: ItemShareCard) -> Data? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(card.shape.size)
        guard let image = renderer.cgImage,
              let output = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

// MARK: - Card Image File (Transferable)

struct ItemShareCardFile: Transferable, Sendable {
    let pngData: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.pngData }
            .suggestedFileName { $0.filename }
    }
}
