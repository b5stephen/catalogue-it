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
    @State private var detent: PresentationDetent = .medium
    @State private var hasSizedToNotes = false

    private static let sheetInset: CGFloat = 16
    private static let textInset: CGFloat = 8
    private static let editorCornerRadius = AppConstants.CornerRadius.medium

    /// Matches a `Form` row, so the field reads like the fields in the other edit sheets.
#if os(iOS)
    private static let fieldBackground = Color(uiColor: .secondarySystemGroupedBackground)
#else
    private static let fieldBackground = Color(nsColor: .controlBackgroundColor)
#endif

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
                .scrollContentBackground(.hidden)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    expandIfNotesOverflow(editorSize: size)
                }
                .padding(Self.textInset)
                .overlay(alignment: .topLeading) {
                    // `TextEditor` has no placeholder. Inert, so the tap still lands in the editor.
                    if notes.isEmpty {
                        Text("Add notes…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Self.textInset + 5)
                            .padding(.top, Self.textInset + 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(Self.fieldBackground, in: .rect(cornerRadius: Self.editorCornerRadius, style: .continuous))
                .padding(Self.sheetInset)
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
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // A swipe-down would silently drop edits.
        .interactiveDismissDisabled(hasChanges)
        // On iPhone the keyboard leaves no room for the medium detent, so focusing on open pushes
        // the sheet to full height. Only jump straight into typing when there's nothing to read.
        .onAppear { isEditorFocused = notes.isEmpty }
    }

    // MARK: - Actions

    /// Decided once, from the first layout at the medium detent; after that the height is the user's.
    private func expandIfNotesOverflow(editorSize: CGSize) {
        guard !hasSizedToNotes, editorSize.width > 0, editorSize.height > 0 else { return }
        hasSizedToNotes = true
#if os(iOS)
        if !notes.isEmpty && Self.textHeight(of: notes, width: editorSize.width) > editorSize.height {
            detent = .large
        }
#endif
    }

#if os(iOS)
    /// Measured with TextKit rather than a hidden `Text`, whose first layout pass can be at zero width.
    /// The insets are `UITextView`'s defaults: 5pt line-fragment padding, 8pt top and bottom.
    private static func textHeight(of text: String, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width - 10, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.preferredFont(forTextStyle: .body)],
            context: nil
        )
        return bounds.height.rounded(.up) + 16
    }
#endif

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
