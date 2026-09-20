//
//  ModelContextUndoModifier.swift
//  catalogue-it
//

import SwiftUI
import SwiftData

private struct ModelContextUndoModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Assign the system UndoManager (already wired to iOS shake-to-undo
                // and macOS Cmd+Z) to the model context. SwiftData then registers every
                // property mutation, insert, and delete as an undoable step on it.
                modelContext.undoManager = undoManager
            }
    }
}

extension View {
    func withModelContextUndoManager() -> some View {
        modifier(ModelContextUndoModifier())
    }
}

nonisolated extension ModelContext {
    /// Runs `body` with undo registration off, for writes that are not the user's to undo:
    /// hard deletes the confirmation promised were permanent, and derived-column upkeep
    /// (sort keys, search blob, facet mirrors) after a merge or a backfill — "undoing" those
    /// would put stale values back and export them.
    func withUndoRegistrationSuspended<T>(_ body: () throws -> T) rethrows -> T {
        let undoManager = self.undoManager
        self.undoManager = nil
        defer { self.undoManager = undoManager }
        return try body()
    }

    /// `withUndoRegistrationSuspended` for a body that suspends. User edits made during
    /// the body's awaits are not registered either, so keep such bodies short.
    func withUndoRegistrationSuspended<T>(_ body: () async throws -> T) async rethrows -> T {
        let undoManager = self.undoManager
        self.undoManager = nil
        defer { self.undoManager = undoManager }
        return try await body()
    }
}
