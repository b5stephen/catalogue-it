//
//  EditItemNotesSheet.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 13/09/2026.
//

import SwiftUI
import SwiftData

// MARK: - Edit Item Notes Sheet

/// Edits an item's notes on their own, without the full edit screen. Opened from the notes
/// card on the item detail screen.
///
/// The editor fills the sheet rather than growing with its text: it shrinks above the keyboard
/// and scrolls internally, so the cursor can never end up underneath the keyboard however much
/// is typed or pasted. That is the whole reason this is a `TextEditor` and not the vertical
/// `TextField` used elsewhere.
struct EditItemNotesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let item: CatalogueItem

    @State private var notes: String
    @FocusState private var isEditorFocused: Bool

    init(item: CatalogueItem) {
        self.item = item
        _notes = State(initialValue: item.notes ?? "")
    }

    // MARK: - Computed

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedNotes != (item.notes ?? "")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            TextEditor(text: $notes)
                .focused($isEditorFocused)
                .padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    // `TextEditor` has no placeholder of its own. Inset to sit on the first
                    // line of text, and inert so the tap still lands in the editor.
                    if notes.isEmpty {
                        Text("Add notes…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .navigationTitle("Notes")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark", action: cancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark", action: save)
                    }
                }
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
#endif
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // A swipe-down with edits pending would silently throw them away; make that go
        // through the explicit cancel instead.
        .interactiveDismissDisabled(hasChanges)
        .onAppear { isEditorFocused = true }
    }

    // MARK: - Actions

    private func cancel() {
        dismiss()
    }

    private func save() {
        // Same normalisation as the full edit screen, so "" and nil don't drift apart.
        item.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        // Saved now rather than left to autosave, so the change reaches iCloud promptly.
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: Catalogue.self, configurations: config)

    let item = CatalogueItem(notes: "Bought at the Hornby show, 2024.")
    container.mainContext.insert(item)

    return EditItemNotesSheet(item: item)
        .modelContainer(container)
}
