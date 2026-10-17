//
//  CatalogueEmptyStateView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI

// MARK: - Empty State View

struct CatalogueEmptyStateView: View {
    let catalogue: Catalogue
    let statusTab: StatusTab
    let hasActiveFlags: Bool
    let isFiltered: Bool

    /// A real status, not "All", so the copy can name it.
    private var selectedStatusDescriptor: StatusTabDescriptor? {
        guard statusTab != .all else { return nil }
        return catalogue.statusTabDescriptors.first { $0.tab == statusTab }
    }

    var body: some View {
        if isFiltered {
            ContentUnavailableView.search
        } else if hasActiveFlags {
            // The catalogue may be full, just not of flagged items.
            ContentUnavailableView(
                "No Matching Items",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No items match the filters you've turned on")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let descriptor = selectedStatusDescriptor {
            ContentUnavailableView(
                "No Items Yet",
                systemImage: descriptor.systemImage,
                description: Text("Tap + to add your first item to \(descriptor.label)")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Items Yet",
                systemImage: "tray.2",
                description: Text("Tap + to add your first item")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
