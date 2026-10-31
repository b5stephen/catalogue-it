//
//  ItemLayoutSettingsView.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Item Layout Settings

struct ItemLayoutSettingsView: View {
    @Binding var layoutOptions: CatalogueLayoutOptions

    var body: some View {
        Form {
            Section {
                // The thumbnails are the control, so VoiceOver gets the single-choice picker they stand for.
                HStack(alignment: .top, spacing: 12) {
                    ForEach(DetailLabelLayout.allCases) { layout in
                        DetailLayoutOption(
                            layout: layout,
                            isSelected: layoutOptions.detailLabelLayout == layout
                        ) {
                            withAnimation(.snappy(duration: 0.2)) {
                                layoutOptions.detailLabelLayout = layout
                            }
                        }
                    }
                }
                .accessibilityRepresentation {
                    Picker("Item Details", selection: $layoutOptions.detailLabelLayout) {
                        ForEach(DetailLabelLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                }
            } header: {
                Text("Item Details")
            } footer: {
                Text("How fields are shown on an item's page.")
            }

            Section {
                SampleListRow(showsPhoto: layoutOptions.showPhotosInList)
                Toggle("Photos in Item List", isOn: $layoutOptions.showPhotosInList)
            } header: {
                Text("Item List")
            } footer: {
                Text("Show each item's first photo as a thumbnail. Turning it off fits more items on screen.")
            }
        }
        .navigationTitle("Item Layout")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

// MARK: - Detail Layout Option

private struct DetailLayoutOption: View {
    let layout: DetailLabelLayout
    let isSelected: Bool
    let action: () -> Void

    private static let cardCornerRadius = AppConstants.CornerRadius.medium
    private static let cardPadding: CGFloat = 8
    /// Inner radius = outer − padding (see the card-design skill).
    private static let illustrationCornerRadius = cardCornerRadius - cardPadding

    private static let lines: [(label: String, value: String)] = [
        ("Manufacturer", "Airfix"),
        ("Scale", "1:48"),
        ("Year", "2019"),
    ]

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                illustration
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    Text(layout.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                }
            }
            .padding(Self.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                .fill.quaternary,
                in: .rect(cornerRadius: Self.cardCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: Self.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var illustration: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.lines, id: \.label) { line in
                switch layout {
                case .beside:
                    HStack(spacing: 4) {
                        Text(line.label).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(line.value)
                    }
                case .above:
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.label).foregroundStyle(.secondary)
                        Text(line.value)
                    }
                }
            }
        }
        // Fixed size: the illustration scales with the card, not with Dynamic Type.
        .font(.system(size: 10))
        .lineLimit(1)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            .background,
            in: .rect(cornerRadius: Self.illustrationCornerRadius, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Sample List Row

/// Matches `ItemRowView`'s thumbnail size and corner radius.
private struct SampleListRow: View {
    let showsPhoto: Bool

    var body: some View {
        HStack(spacing: 12) {
            if showsPhoto {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
                    .frame(width: AppConstants.ThumbnailSize.list, height: AppConstants.ThumbnailSize.list)
                    .background(
                        .fill.tertiary,
                        in: .rect(cornerRadius: AppConstants.ItemCard.thumbnailCornerRadius, style: .continuous)
                    )
                    .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Item name")
                    .font(.headline)
                Text("Field: value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .animation(.default, value: showsPhoto)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sample item row")
        .accessibilityValue(showsPhoto ? Text("With photo") : Text("Without photo"))
    }
}

// MARK: - Preview

#Preview("Item Layout") {
    @Previewable @State var options = CatalogueLayoutOptions()

    NavigationStack {
        ItemLayoutSettingsView(layoutOptions: $options)
    }
}
