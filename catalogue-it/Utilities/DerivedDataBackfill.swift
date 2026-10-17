//
//  DerivedDataBackfill.swift
//  catalogue-it
//

import Foundation
import SwiftData
import os

// MARK: - Derived Data Backfill

/// Runs at launch when this device's recorded `SearchTextBuilder.formatVersion` is behind,
/// recording the new one only once the whole store is done, so a killed sweep resumes. Writes
/// only rows that differ. An older build on another device keeps writing its own format, and
/// each side rewrites what the other merges in until it updates — so change the rules rarely.
@MainActor
enum DerivedDataBackfill {
    private static let logger = Logger(subsystem: "catalogue-it", category: "DerivedDataBackfill")
    static let searchTextVersionKey = "derivedData.searchTextFormatVersion"

    /// On macOS every window runs the launch task; one sweep is enough.
    private static var isRunning = false

    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) async {
        let recorded = defaults.integer(forKey: searchTextVersionKey)
        guard recorded < SearchTextBuilder.formatVersion, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let catalogues = (try? context.fetch(FetchDescriptor<Catalogue>(
            predicate: #Predicate { !$0.pendingDeletion }))) ?? []
        logger.notice("Rebuilding search text from format \(recorded, privacy: .public) to \(SearchTextBuilder.formatVersion, privacy: .public) across \(catalogues.count, privacy: .public) catalogues")

        await context.withUndoRegistrationSuspended {
            for catalogue in catalogues {
                await CatalogueSortKeyMaintenance.recomputeDerivedData(for: catalogue, in: context)
            }
        }
        defaults.set(SearchTextBuilder.formatVersion, forKey: searchTextVersionKey)
    }
}
