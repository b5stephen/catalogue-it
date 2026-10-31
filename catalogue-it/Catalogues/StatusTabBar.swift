//
//  StatusTabBar.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Status Tab Bar

/// A scrolling row of capsules rather than a segmented control, which divides its width and
/// truncates every segment to an ellipsis past a handful of options.
///
/// - Over the ground (`onFill == false`): one glass shelf, so a photo can't show through gaps
///   between pills, with a sliding segment of the tint lettered from the palette (a pale tint
///   needs dark text).
/// - On the band's fill, where tinted glass vanishes into the same colour: the band's own
///   language — the icon tile's pane for the rest, a light pill for the current one.
struct StatusTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let tabs: [StatusTabDescriptor]
    let colorHex: String
    @Binding var selection: StatusTab
    var onFill = false

    @Namespace private var selectionNamespace
    @State private var overflow = ShelfOverflow()

    var body: some View {
        let palette = CataloguePalette(
            hex: colorHex,
            scheme: colorScheme,
            isSelected: false,
            increasedContrast: colorSchemeContrast == .increased
        )

        ScrollViewReader { proxy in
            Group {
                if onFill {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) { tabButtons(palette) }
                            .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                } else {
                    shelf(palette)
                }
            }
            .onChange(of: selection, initial: true) { _, tab in
                // It may come from the default or a reconcile rather than a tap.
                withAnimation { proxy.scrollTo(tab, anchor: .center) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
    }

    /// Hugs the tabs while they fit, then stops at the column's width with the tabs scrolling
    /// inside it; the end with tabs hidden past it fades.
    private func shelf(_ palette: CataloguePalette) -> some View {
        // The segments share one pane, so the gaps need only separate the labels.
        let row = HStack(spacing: 2) { tabButtons(palette) }
            .padding(3)

        return ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal) {
                row.scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: ShelfOverflow.self) { geometry in
                ShelfOverflow(
                    leading: geometry.contentOffset.x > 1,
                    trailing: geometry.contentOffset.x + geometry.containerSize.width
                        < geometry.contentSize.width - 1
                )
            } action: { _, newValue in
                overflow = newValue
            }
            .mask {
                HStack(spacing: 0) {
                    edgeFade(isFaded: overflow.leading, startPoint: .trailing, endPoint: .leading)
                    Color.black
                    edgeFade(isFaded: overflow.trailing, startPoint: .leading, endPoint: .trailing)
                }
            }
            .clipShape(.capsule)
        }
        .glassEffect(shelfGlass, in: .capsule)
    }

    private func edgeFade(isFaded: Bool, startPoint: UnitPoint, endPoint: UnitPoint) -> some View {
        LinearGradient(
            colors: [.black, isFaded ? .clear : .black],
            startPoint: startPoint,
            endPoint: endPoint
        )
        .frame(width: 28)
    }

    private func tabButtons(_ palette: CataloguePalette) -> some View {
        ForEach(tabs) { descriptor in
            let isOn = descriptor.tab == selection
            Button {
                withAnimation(.snappy(duration: 0.25)) { selection = descriptor.tab }
            } label: {
                Text(descriptor.label)
                    .font(.subheadline.weight(isOn ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(labelColor(isOn: isOn, palette: palette))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background {
                if onFill {
                    Capsule().fill(isOn ? Color.white.opacity(0.95) : palette.iconTint)
                } else if isOn {
                    // One segment moved between tabs, so a change reads as sliding along the shelf.
                    Capsule()
                        .fill(palette.tint)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .id(descriptor.tab)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
        }
    }

    private func labelColor(isOn: Bool, palette: CataloguePalette) -> Color {
        if onFill {
            guard isOn else { return palette.primaryText }
            // The fill's deep stop, which is pale too when the fill's labels went dark.
            return palette.prefersDarkForeground ? palette.primaryText : palette.fillDeepStop
        }
        return isOn ? palette.primaryText : palette.tint
    }

    /// Plain glass over the black ground is near invisible, so a faint white tint frosts it; in
    /// light the glow does that.
    private var shelfGlass: Glass {
        colorScheme == .dark ? .regular.tint(.white.opacity(0.14)) : .regular
    }
}

private struct ShelfOverflow: Equatable {
    var leading = false
    var trailing = false
}

// MARK: - Preview

#Preview("Fits") {
    @Previewable @State var selection: StatusTab = .all
    VStack {
        StatusTabBar(
            tabs: [
                StatusTabDescriptor(tab: .all, label: "All", systemImage: "tray.2.fill"),
                StatusTabDescriptor(tab: .option("Owned"), label: "Owned", systemImage: "circle.fill"),
                StatusTabDescriptor(tab: .option("Wishlist"), label: "Wishlist", systemImage: "circle.fill"),
            ],
            colorHex: "#007AFF",
            selection: $selection
        )
        .padding()
        Spacer()
    }
}

#Preview("Overflows — scrolls") {
    @Previewable @State var selection: StatusTab = .option("Restoring")
    VStack {
        StatusTabBar(
            tabs: [StatusTabDescriptor(tab: .all, label: "All", systemImage: "tray.2.fill")]
                + ["Owned", "Wishlist", "Ordered", "Restoring", "Sold", "On Loan"].map {
                    StatusTabDescriptor(tab: .option($0), label: $0, systemImage: "circle.fill")
                },
            colorHex: "#5C1A22",
            selection: $selection
        )
        .padding()
        Spacer()
    }
}
