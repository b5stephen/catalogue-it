//
//  StatusTabBar.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Status Tab Bar

/// The item list's status filter, rendered as a segmented control when the tabs fit and as
/// a pull-down menu when they don't.
///
/// A catalogue's status field can carry any number of options, so the tab bar cannot assume
/// a segmented control is viable: `UISegmentedControl` divides its width evenly and then
/// truncates, so past a handful of tabs — or a couple of long option names — every segment
/// reads as an ellipsis or an empty sliver and the options effectively disappear.
///
/// Rather than capping the option count, the bar measures the tabs at their natural width
/// and falls back to a menu once they no longer fit. The measurement is a hidden copy of the
/// labels laid out with `fixedSize()` in a background — a background is proposed the
/// container's size but never contributes to it, so the real control's layout is unaffected.
/// Until the first measurement lands the menu is shown: it is correct at every width, so
/// starting there means the bar never flashes a truncated segmented control.
///
/// Deliberately `Text`, not `Label`, in the segmented case. A segmented control renders a
/// `Label` as its icon alone, which is why every option-list tab used to show the same
/// anonymous dot; the icons are kept for the menu, where they render alongside the title.
struct StatusTabBar: View {
    let tabs: [StatusTabDescriptor]
    @Binding var selection: StatusTab

    /// Width offered to the bar, and the width the segments want. Both start at zero,
    /// which reads as "not yet measured" — see `fitsSegmented`.
    @State private var availableWidth: CGFloat = 0
    @State private var naturalSegmentedWidth: CGFloat = 0

    /// Horizontal padding a segmented control puts either side of a segment's title.
    /// Only an approximation of UIKit's metrics, so the comparison leaves a little slack.
    private static let segmentPadding: CGFloat = 14

    private var fitsSegmented: Bool {
        guard availableWidth > 0, naturalSegmentedWidth > 0 else { return false }
        return naturalSegmentedWidth <= availableWidth
    }

    private var selectedLabel: String {
        tabs.first { $0.tab == selection }?.label ?? tabs.first?.label ?? ""
    }

    var body: some View {
        Group {
            if fitsSegmented {
                segmentedPicker
            } else {
                menuPicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) { widthProbe }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    // MARK: - Presentations

    private var segmentedPicker: some View {
        Picker("Status", selection: $selection) {
            ForEach(tabs) { descriptor in
                Text(descriptor.label).tag(descriptor.tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var menuPicker: some View {
        Menu {
            // Inline so the menu shows every tab at once with a checkmark on the current
            // one, rather than a submenu the user has to open first.
            Picker("Status", selection: $selection) {
                ForEach(tabs) { descriptor in
                    Label(descriptor.label, systemImage: descriptor.systemImage)
                        .tag(descriptor.tab)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(selectedLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Status")
        .accessibilityValue(selectedLabel)
    }

    // MARK: - Measurement

    /// A hidden, unclipped copy of the segment titles at their natural width. Hidden views
    /// still take part in layout, so this reports what a segmented control would need.
    private var widthProbe: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { descriptor in
                Text(descriptor.label)
                    .font(.subheadline)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, Self.segmentPadding)
            }
        }
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { naturalSegmentedWidth = $0 }
    }
}

// MARK: - Preview

#Preview("Fits — Segmented") {
    @Previewable @State var selection: StatusTab = .all
    VStack {
        StatusTabBar(
            tabs: [
                StatusTabDescriptor(tab: .all, label: "All", systemImage: "tray.2.fill"),
                StatusTabDescriptor(tab: .option("Owned"), label: "Owned", systemImage: "circle.fill"),
                StatusTabDescriptor(tab: .option("Wishlist"), label: "Wishlist", systemImage: "circle.fill"),
            ],
            selection: $selection
        )
        .padding()
        Spacer()
    }
}

#Preview("Too Many — Menu") {
    @Previewable @State var selection: StatusTab = .option("Restoring")
    VStack {
        StatusTabBar(
            tabs: [StatusTabDescriptor(tab: .all, label: "All", systemImage: "tray.2.fill")]
                + ["Owned", "Wishlist", "Ordered", "Restoring", "Sold", "On Loan"].map {
                    StatusTabDescriptor(tab: .option($0), label: $0, systemImage: "circle.fill")
                },
            selection: $selection
        )
        .padding()
        Spacer()
    }
}
