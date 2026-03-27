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
