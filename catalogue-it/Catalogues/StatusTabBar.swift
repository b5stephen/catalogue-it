//
//  StatusTabBar.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Status Tab Bar

/// The item list's status filter: a row of capsules in the catalogue's tint, the current one
/// filled.
///
/// A catalogue's status field can carry any number of options, so the bar cannot assume they
/// fit: a segmented control divides its width evenly and then truncates, so past a handful of
/// tabs every segment read as an ellipsis. A horizontally scrolling row sidesteps that — each
/// capsule takes its natural width, and the row scrolls once they overflow, with the current
/// tab kept in view.
///
/// Where the bar sits decides how the capsules are drawn:
///
/// - Over the ground (`onFill == false`, beside a detail column), the row sits on one glass
///   shelf, with the current tab a solid segment of the catalogue's tint sliding inside it.
///   The bar floats over cards passing beneath, and separate glass pills left gaps between
///   them where a photo showed through at full strength; a single pane frosts the whole row.
///   The segment's label comes from the palette rather than being white, since a pale pick
///   (a yellow, say) needs dark text to clear its own colour.
/// - On the catalogue band's fill, glass tinted with the catalogue colour disappears into a
///   fill of that same colour. There the tabs take the band's own language instead, the way a
///   segmented control sits on a coloured bar: the icon tile's translucent pane for the rest,
///   and a light pill for the current one, lettered in the fill's deep stop.
struct StatusTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let tabs: [StatusTabDescriptor]
    let catalogue: Catalogue
    @Binding var selection: StatusTab
    var onFill = false

    @Namespace private var selectionNamespace
    /// Which ends of the shelf have tabs scrolled out of sight past them.
    @State private var overflow = ShelfOverflow()

    var body: some View {
        let palette = catalogue.palette(
            for: colorScheme,
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
                // Keep the current tab visible — it may have been chosen from the catalogue's
                // default rather than by a tap, or reconciled after the field was reconfigured.
                withAnimation { proxy.scrollTo(tab, anchor: .center) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
    }

    /// The glass shelf. It hugs the tabs while they fit; once they don't, the shelf stops at
    /// the column's width and the tabs scroll *inside* it, the way a segmented control would,
    /// rather than the whole capsule scrolling and being sliced off at the column's edge.
    /// The end with tabs hidden past it fades, which is what says there is more to scroll.
    private func shelf(_ palette: CataloguePalette) -> some View {
        // Tighter than the pills: the segments share one pane, so the gaps only need to
        // separate the labels.
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
                    // One segment, moved between tabs rather than faded in and out, so a
                    // change of tab reads as the selection sliding along the shelf.
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
            // On the white pill: the fill's own deep stop, unless the fill is pale enough that
            // its labels went dark — then the deep stop is pale too, and the dark label reads.
            return palette.prefersDarkForeground ? palette.primaryText : palette.fillDeepStop
        }
        return isOn ? palette.primaryText : palette.tint
    }

    /// Plain glass over the black ground is close to invisible — there is nothing light behind
    /// it to catch. A faint white tint frosts it enough to read as a shelf without becoming a
    /// button. In light appearance the glow itself provides that, so the glass is left clear.
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
            catalogue: Catalogue(name: "Model Planes", iconName: "airplane", colorHex: "#007AFF"),
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
            catalogue: Catalogue(name: "Vintage Wine", iconName: "wineglass", colorHex: "#5C1A22"),
            selection: $selection
        )
        .padding()
        Spacer()
    }
}
