//
//  ExportFilters.swift
//  catalogue-it
//

import Foundation

// MARK: - Export Scope

nonisolated enum ExportScope: CaseIterable, Identifiable {
    case filtered
    case all

    var id: Self { self }
}

// MARK: - Export Filters

/// The list's filters when the composer opens from the toolbar, so it can offer the whole
/// catalogue instead.
nonisolated struct ExportFilters: Equatable, Sendable {
    let fingerprint: FilterFingerprint
    let allCount: Int

    /// `nil` when the list shows everything, since there is nothing to choose between.
    init?(fingerprint: FilterFingerprint, allCount: Int) {
        guard !fingerprint.hasSameFilters(as: fingerprint.unfiltered) else { return nil }
        self.fingerprint = fingerprint
        self.allCount = allCount
    }

    func selection(for scope: ExportScope) -> ItemSelection {
        .matching(scope == .filtered ? fingerprint : fingerprint.unfiltered, excluding: [])
    }
}
