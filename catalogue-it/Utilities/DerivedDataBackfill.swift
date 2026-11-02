//
//  DerivedDataBackfill.swift
//  catalogue-it
//

import Foundation
import SwiftData
import os

// MARK: - Derived Data Backfill

/// Runs at launch when this device's recorded `SearchTextBuilder.formatVersion` or
/// `SortKeyEncoder.formatVersion` is behind, recording the new ones only once the whole store is
/// done, so a killed sweep resumes. The sweep rebuilds every derived column either way. Writes
/// only rows that differ. An older build on another device keeps writing its own format, and
/// each side rewrites what the other merges in until it updates — so change the rules rarely.
@MainActor
enum DerivedDataBackfill {
    private static let logger = Logger(subsystem: "catalogue-it", category: "DerivedDataBackfill")
    static let searchTextVersionKey = "derivedData.searchTextFormatVersion"
    static let sortKeyVersionKey = "derivedData.sortKeyFormatVersion"

    /// On macOS every window runs the launch task; one sweep is enough.
    private static var isRunning = false

    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) async {
        let recorded = defaults.integer(forKey: searchTextVersionKey)
        let recordedSortKey = defaults.integer(forKey: sortKeyVersionKey)
        guard recorded < SearchTextBuilder.formatVersion || recordedSortKey < SortKeyEncoder.formatVersion,
              !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let catalogues = (try? context.fetch(FetchDescriptor<Catalogue>(
            predicate: #Predicate { !$0.pendingDeletion }))) ?? []
        logger.notice("Rebuilding derived data (search text \(recorded, privacy: .public)→\(SearchTextBuilder.formatVersion, privacy: .public), sort keys \(recordedSortKey, privacy: .public)→\(SortKeyEncoder.formatVersion, privacy: .public)) across \(catalogues.count, privacy: .public) catalogues")

        await context.withUndoRegistrationSuspended {
            for catalogue in catalogues {
                await CatalogueSortKeyMaintenance.recomputeDerivedData(for: catalogue, in: context)
            }
        }
        defaults.set(SearchTextBuilder.formatVersion, forKey: searchTextVersionKey)
        defaults.set(SortKeyEncoder.formatVersion, forKey: sortKeyVersionKey)
    }
}
