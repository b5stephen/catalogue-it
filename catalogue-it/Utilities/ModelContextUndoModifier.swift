//
//  ModelContextUndoModifier.swift
//  catalogue-it
//

import SwiftUI
import SwiftData
import os

private struct ModelContextUndoModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Assign the system UndoManager (already wired to iOS shake-to-undo
                // and macOS Cmd+Z) to the model context. SwiftData then registers every
                // property mutation, insert, and delete as an undoable step on it.
                modelContext.setDesiredUndoManager(undoManager)
            }
    }
}

extension View {
    func withModelContextUndoManager() -> some View {
        modifier(ModelContextUndoModifier())
    }
}

// MARK: - Undo Registration Gate

/// SwiftData snapshots a model when it is mutated *with* an undo manager attached, and
/// `save()` then builds the undo record from that snapshot. Attaching an undo manager to a
/// context that already holds changes made without one therefore crashes the next save
/// (`_newSnapshotForUndo__`: "A snapshot should exist before creating a new snapshot for
/// undo" — TestFlight 0.6.0 (5), every launch). Every change to `undoManager` goes through
/// this gate so that can't happen: the modifier above records what it wants attached, and
/// the suspension below decides when that actually takes effect.
@MainActor
private final class UndoRegistrationState {
    var desired: UndoManager?
    var suspensionDepth = 0
}

@MainActor
private let undoRegistrationStates = NSMapTable<ModelContext, UndoRegistrationState>.weakToStrongObjects()

@MainActor
extension ModelContext {
    private var undoRegistrationState: UndoRegistrationState {
        if let state = undoRegistrationStates.object(forKey: self) { return state }
        let state = UndoRegistrationState()
        undoRegistrationStates.setObject(state, forKey: self)
        return state
    }

    /// The undo manager this context should register on when nothing is suspending
    /// registration. Applied immediately if nothing is; otherwise when the last suspension
    /// ends. This is the only place `undoManager` should be assigned from.
    func setDesiredUndoManager(_ undoManager: UndoManager?) {
        let state = undoRegistrationState
        state.desired = undoManager
        guard state.suspensionDepth == 0 else { return }
        attach(undoManager)
    }

    /// Runs `body` with undo registration off, for writes that are not the user's to undo:
    /// hard deletes the confirmation promised were permanent, and derived-column upkeep
    /// (sort keys, search blob, facet mirrors) after a merge or a backfill — "undoing" those
    /// would put stale values back and export them.
    func withUndoRegistrationSuspended<T>(_ body: () throws -> T) rethrows -> T {
        beginUndoSuspension()
        defer { endUndoSuspension() }
        return try body()
    }

    /// `withUndoRegistrationSuspended` for a body that suspends. User edits made during
    /// the body's awaits are not registered either, so keep such bodies short.
    func withUndoRegistrationSuspended<T>(_ body: () async throws -> T) async rethrows -> T {
        beginUndoSuspension()
        defer { endUndoSuspension() }
        return try await body()
    }

    private func beginUndoSuspension() {
        undoRegistrationState.suspensionDepth += 1
        undoManager = nil
    }

    private func endUndoSuspension() {
        let state = undoRegistrationState
        state.suspensionDepth -= 1
        guard state.suspensionDepth == 0 else { return }
        attach(state.desired)
    }

    /// Anything pending while no manager is attached was changed without a snapshot, and
    /// attaching over it crashes the next save. Suspended bodies save before returning, so
    /// this normally finds nothing; it catches an edit made during a body's await, or a write
    /// that ran before the undo modifier's onAppear. A save that fails is rolled back rather
    /// than left pending — losing that edit beats a guaranteed crash on the user's next save.
    private func attach(_ manager: UndoManager?) {
        if undoManager == nil, manager != nil, hasChanges {
            do {
                try save()
            } catch {
                rollback()
                Logger(subsystem: "catalogue-it", category: "UndoRegistration")
                    .error("Save before attaching undo failed, rolled back: \(error, privacy: .public)")
            }
        }
        undoManager = manager
    }
}
