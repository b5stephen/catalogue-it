//
//  CatalogueHeaderSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Catalogue Header Section

/// Icon, name and colour in one card. The colour well is the last swatch, ringed when the
/// current colour isn't a palette one.
struct CatalogueHeaderSection: View {
    @Binding var name: String
    let iconName: String
    @Binding var color: Color
    let onChangeIcon: () -> Void

    @FocusState private var isNameFocused: Bool

    private typealias Metrics = AppConstants.CatalogueHeader

    /// Keeps the columns from drifting apart in a wide sheet.
    private static let swatchGridMaxWidth: CGFloat = 300
    private static let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 5)

    /// Keyed by `CatalogueColorSuggester.palette`; a hex missing here is read out as is.
    private static let swatchNames: [String: String] = [
        "#007AFF": String(localized: "Blue"),
        "#FF9500": String(localized: "Orange"),
        "#34C759": String(localized: "Green"),
        "#AF52DE": String(localized: "Purple"),
        "#FF3B30": String(localized: "Red"),
        "#30B0C7": String(localized: "Teal"),
        "#FF2D55": String(localized: "Pink"),
        "#FFCC00": String(localized: "Yellow"),
        "#5856D6": String(localized: "Indigo"),
    ]

    private var currentHex: String { color.toHex() }

    private var isCustomColor: Bool {
        !CatalogueColorSuggester.palette.contains { $0.caseInsensitiveCompare(currentHex) == .orderedSame }
    }

    var body: some View {
        Section {
            VStack(spacing: 16) {
                iconButton
                nameField
                swatches
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(
                top: Metrics.contentPadding,
                leading: Metrics.contentPadding,
                bottom: Metrics.contentPadding,
                trailing: Metrics.contentPadding
            ))
        }
    }

    // MARK: - Icon

    private var iconButton: some View {
        Button(action: onChangeIcon) {
            CatalogueIconView(iconName: iconName, color: color, size: 36)
                .frame(width: Metrics.iconTile, height: Metrics.iconTile)
                .background(
                    color.opacity(0.15),
                    in: .rect(cornerRadius: Metrics.iconTileCornerRadius, style: .continuous)
                )
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.background, in: .circle)
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                        .offset(x: 6, y: 6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change Icon")
    }

    // MARK: - Name

    private var nameField: some View {
        TextField("Name", text: $name)
#if os(iOS)
            .textInputAutocapitalization(.words)
#endif
            .focused($isNameFocused)
            .accessibilityIdentifier("catalogue-name-field")
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                .fill.tertiary,
                in: .rect(cornerRadius: Metrics.nameFieldCornerRadius, style: .continuous)
            )
            .contentShape(.rect)
            .onTapGesture { isNameFocused = true }
    }

    // MARK: - Colour

    // Two rows of five: ten 44pt targets don't fit one row at iPhone width, and a fixed column
    // count keeps the rows balanced at any width.
    private var swatches: some View {
        LazyVGrid(columns: Self.swatchColumns, spacing: 0) {
            ForEach(CatalogueColorSuggester.palette, id: \.self) { hex in
                swatch(hex: hex)
            }
            customSwatch
        }
        .frame(maxWidth: Self.swatchGridMaxWidth)
    }

    private func swatch(hex: String) -> some View {
        let isSelected = !isCustomColor && hex.caseInsensitiveCompare(currentHex) == .orderedSame
        return Button {
            color = Color(hex: hex)
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: Metrics.swatch, height: Metrics.swatch)
                .modifier(SwatchRing(isSelected: isSelected))
                .frame(width: Metrics.swatchTapSize, height: Metrics.swatchTapSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.swatchNames[hex.uppercased()] ?? hex)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customSwatch: some View {
        ColorPicker("Custom Color", selection: $color, supportsOpacity: false)
            .labelsHidden()
            .frame(width: Metrics.swatch, height: Metrics.swatch)
            .modifier(SwatchRing(isSelected: isCustomColor))
            .frame(width: Metrics.swatchTapSize, height: Metrics.swatchTapSize)
    }
}

// MARK: - Swatch Ring

/// Drawn outside the swatch's bounds, so selecting one doesn't shift the grid.
private struct SwatchRing: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isSelected {
                Circle()
                    .stroke(.secondary, lineWidth: 2.5)
                    .padding(-4.5)
            }
        }
    }
}
