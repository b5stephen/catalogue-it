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
                // The system UndoManager is already wired to shake-to-undo and Cmd+Z.
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

/// Attaching an undo manager to a context that already holds changes made without one crashes
/// the next save (`_newSnapshotForUndo__`), since undo records come from snapshots taken at
/// mutation. Every change to `undoManager` goes through this gate.
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

    /// Applied now, or when the last suspension ends. The only place `undoManager` should be
    /// assigned from.
    func setDesiredUndoManager(_ undoManager: UndoManager?) {
        let state = undoRegistrationState
        state.desired = undoManager
        guard state.suspensionDepth == 0 else { return }
        attach(undoManager)
    }

    /// For writes that aren't the user's to undo: permanent hard deletes, and derived-column
    /// upkeep, which on the undo stack would put stale values back and export them.
    func withUndoRegistrationSuspended<T>(_ body: () throws -> T) rethrows -> T {
        beginUndoSuspension()
        defer { endUndoSuspension() }
        return try body()
    }

    /// User edits during the body's awaits aren't registered either, so keep it short.
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

    /// Pending changes made without a manager would crash the next save once one is attached.
    /// Normally empty; catches an edit made during a body's await, or a write before the
    /// modifier's onAppear. A failed save is rolled back: losing that edit beats a crash.
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
