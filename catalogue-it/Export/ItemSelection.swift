//
//  ItemSelection.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Item Selection

/// Which items select mode has picked. Select All is `matching`, so it never loads the pages
/// it covers; it resolves to IDs only when something acts on it.
nonisolated enum ItemSelection: Equatable, Sendable {
    case items(Set<PersistentIdentifier>)
    /// Everything the fingerprint shows, minus the items unticked since.
    case matching(FilterFingerprint, excluding: Set<PersistentIdentifier>)

    static let none = ItemSelection.items([])

    func contains(_ id: PersistentIdentifier) -> Bool {
        switch self {
        case .items(let ids): ids.contains(id)
        case .matching(_, let excluded): !excluded.contains(id)
        }
    }

    func toggled(_ id: PersistentIdentifier) -> ItemSelection {
        switch self {
        case .items(var ids):
            if !ids.insert(id).inserted { ids.remove(id) }
            return .items(ids)
        case .matching(let fingerprint, var excluded):
            if !excluded.insert(id).inserted { excluded.remove(id) }
            return .matching(fingerprint, excluding: excluded)
        }
    }

    /// `totalMatching` is the list's count for the current filters, which a `matching` selection
    /// covers.
    func count(totalMatching: Int) -> Int {
        switch self {
        case .items(let ids): ids.count
        case .matching(_, let excluded): max(0, totalMatching - excluded.count)
        }
    }

    /// The selection once the list's fingerprint has become `current`. "All of what was showing"
    /// means nothing once the filters move, so it empties; a new sort only reorders it.
    func following(_ current: FilterFingerprint) -> ItemSelection {
        guard case .matching(let fingerprint, let excluded) = self else { return self }
        return fingerprint.hasSameFilters(as: current) ? .matching(current, excluding: excluded) : .none
    }

    // MARK: Resolving

    /// The chosen items in the list's sort, as of `current`. Explicit picks can span filters, so
    /// they are found among every item rather than the ones now showing.
    func resolve(in context: ModelContext, current: FilterFingerprint) throws -> [PersistentIdentifier] {
        switch self {
        case .items(let ids):
            guard !ids.isEmpty else { return [] }
            return try ItemQuery.orderedIDs(for: current.unfiltered, context: context, keeping: ids)
        case .matching(let fingerprint, let excluded):
            let ids = try ItemQuery.orderedIDs(for: fingerprint, context: context)
            return excluded.isEmpty ? ids : ids.filter { !excluded.contains($0) }
        }
    }

    /// On a fresh context off the main thread, so Select All over thousands of items never
    /// touches the UI.
    func resolve(in container: ModelContainer, current: FilterFingerprint) async throws -> [PersistentIdentifier] {
        let selection = self
        let task = Task.detached(priority: .userInitiated) {
            try selection.resolve(in: ModelContext(container), current: current)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
