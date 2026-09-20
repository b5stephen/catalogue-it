//
//  DerivedDataBackfill.swift
//  catalogue-it
//

import Foundation
import SwiftData
import os

// MARK: - Derived Data Backfill

/// Rewrites every item's derived columns once per device when an encoding changes.
///
/// `SearchTextBuilder.formatVersion` names the current rules for the search blob. The
/// version this device last swept to is kept in user defaults; when it is behind, every
/// catalogue is walked through `CatalogueSortKeyMaintenance` at launch. The sweep writes only
/// rows whose columns actually differ, so a text-only catalogue costs a read and no export,
/// and a sweep interrupted by the app being killed simply resumes next launch — the version
/// is recorded only once the whole store is done.
///
/// A device on an older build keeps writing blobs in its own format until it updates, and
/// each version's `RemoteChangeObserver` rewrites what the other merges in. That churn is
/// bounded by how long the two builds coexist, and is the reason the rules should change
/// rarely.
@MainActor
enum DerivedDataBackfill {
    private static let logger = Logger(subsystem: "catalogue-it", category: "DerivedDataBackfill")
    static let searchTextVersionKey = "derivedData.searchTextFormatVersion"

    /// On macOS every window's `ContentView` runs the launch task; one sweep is enough.
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
