//
//  EditItemNotesSheet.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 13/09/2026.
//

import SwiftUI
import SwiftData

// MARK: - Edit Item Notes Sheet

/// A `TextEditor` filling the sheet rather than a growing `TextField`: it shrinks above the
/// keyboard and scrolls internally, so the cursor can't end up under the keyboard.
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
                    // `TextEditor` has no placeholder. Inert, so the tap still lands in the editor.
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
        // A swipe-down would silently drop edits.
        .interactiveDismissDisabled(hasChanges)
        .onAppear { isEditorFocused = true }
    }

    // MARK: - Actions

    private func cancel() {
        dismiss()
    }

    private func save() {
        // Normalised like the full edit screen so "" and nil don't drift apart, and saved now so the
        // change reaches iCloud promptly.
        _ = try? ItemSaveService.updateNotes(notes, on: item, context: modelContext)
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
