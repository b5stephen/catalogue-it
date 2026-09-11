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
/// Solid colour is reserved for the one tab that is current. The text on it comes from the
/// catalogue's palette rather than being white, since a pale pick (a yellow, say) needs dark
/// text to clear its own fill.
struct StatusTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let tabs: [StatusTabDescriptor]
    let catalogue: Catalogue
    @Binding var selection: StatusTab

    @Namespace private var selectionNamespace

    var body: some View {
        let palette = catalogue.palette(
            for: colorScheme,
            increasedContrast: colorSchemeContrast == .increased
        )

        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(tabs) { descriptor in
                        let isOn = descriptor.tab == selection
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { selection = descriptor.tab }
                        } label: {
                            Text(descriptor.label)
                                .font(.subheadline.weight(isOn ? .semibold : .regular))
                                .lineLimit(1)
                                .foregroundStyle(isOn ? palette.primaryText : palette.tint)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background {
                                    if isOn {
                                        Capsule()
                                            .fill(palette.tint)
                                            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(descriptor.tab)
                        .accessibilityAddTraits(isOn ? [.isSelected] : [])
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onChange(of: selection, initial: true) { _, tab in
                // Keep the current tab visible — it may have been chosen from the catalogue's
                // default rather than by a tap, or reconciled after the field was reconfigured.
                withAnimation { proxy.scrollTo(tab, anchor: .center) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
    }
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
