//
//  ThumbnailCacheState.swift
//  catalogue-it
//

import Foundation
import Observation
import SwiftData

// MARK: - Thumbnail Cache State

/// What a thumbnail view keys its load on, and the one piece of process-wide state that can
/// change it from outside the item.
///
/// `ItemCardView` and `ItemRowView` hold their decoded cover image in `@State` and load it in
/// `.task(id:)`. Keyed on the item's identifier alone, that task never re-ran: an edit that
/// replaced the photo evicted the caches correctly, but nothing asked the mounted view to look
/// again, so on iPad — where the list stays on screen while the item is edited — the old
/// image stayed until the whole list was rebuilt. The key now also carries:
///
/// - `modifiedDate`, which the save bumps. Being a model property it also arrives through
///   sync, so a photo swapped on another device reloads here too.
/// - `generation`, bumped by `RemoteChangeObserver` when it clears the caches wholesale. This
///   covers a remote change from a device on a build that predates `modifiedDate`.
@MainActor
@Observable
final class ThumbnailCacheState {
    static let shared = ThumbnailCacheState()

    /// Incremented whenever both thumbnail caches were dropped for reasons no item's
    /// `modifiedDate` reflects.
    private(set) var generation = 0

    func invalidateAll() {
        generation &+= 1
    }
}

/// Identity of one thumbnail load. Equal keys mean the cached image is still the right one.
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
