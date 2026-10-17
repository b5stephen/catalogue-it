//
//  ThumbnailCacheState.swift
//  catalogue-it
//

import Foundation
import Observation
import SwiftData

// MARK: - Thumbnail Cache State

/// Thumbnail views load in `.task(id:)` from `@State`, so the key must change for a mounted
/// view to look again — on iPad the list stays on screen while an item is edited:
/// - `modifiedDate`, bumped by the save, and synced, so a photo swapped elsewhere reloads.
/// - `generation`, bumped when `RemoteChangeObserver` clears the caches.
///
/// Built in `body`, so a bump re-evaluates the whole row. That is relied on: a CloudKit merge
/// bypasses the setters, so observation won't re-render the row, and a pagination reload
/// hands back the same instances.
@MainActor
@Observable
final class ThumbnailCacheState {
    static let shared = ThumbnailCacheState()

    /// Bumped when both caches were dropped for reasons no item's `modifiedDate` reflects.
    private(set) var generation = 0

    func invalidateAll() {
        generation &+= 1
    }
}

/// Equal keys mean the cached image is still right.
struct ThumbnailKey: Equatable {
    let itemID: PersistentIdentifier
    let modifiedDate: Date
    let generation: Int

    @MainActor
    init(item: CatalogueItem) {
        itemID = item.persistentModelID
        modifiedDate = item.modifiedDate
        generation = ThumbnailCacheState.shared.generation
    }
}
