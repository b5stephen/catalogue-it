//
//  ItemDetailSections.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 16/03/2026.
//

import SwiftUI

// MARK: - Field Row

/// One field of the item, in the catalogue's chosen `DetailLabelLayout`.
///
/// `.beside`: label on the left, value on the right, on one line — the same shape as the
/// status row, so a card of mixed fields reads as one table. A value too long for the
/// remaining width wraps beneath itself, trailing-aligned, rather than flipping the row into
/// a different layout from its neighbours; the label keeps its width so it is never the thing
/// that gets squashed. Only a genuine block of text (a paragraph, several lines) drops below
/// the label, and then with the same label styling so the row still reads as part of the
/// same table.
///
/// `.above`: every row is label over value, left-aligned, whatever its length. Since every
/// row shares the shape, the label can drop to a caption — it's a heading, not a column.
private struct FieldRowView: View {
    let label: String
    let value: String
    let layout: DetailLabelLayout
    /// The rows sit inside a card, so the last one draws no divider against the card's edge.
    var isLast: Bool = false

    /// A value that would take several lines even at full width has no business in a trailing
    /// column; it reads as prose, so it is laid out as prose.
    private var isBlockOfText: Bool {
        value.contains("\n") || value.count > 80
    }

    private var isStacked: Bool {
        layout == .above || isBlockOfText
    }

    /// A block of text stacked among inline rows keeps the body-size label so it still reads
    /// as one of them; under `.above` every label is a heading, and a caption suits that.
    private var stackedLabelFont: Font {
        layout == .above ? .caption : .body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if isStacked {
                    VStack(alignment: .leading, spacing: layout == .above ? 2 : 4) {
                        Text(label)
                            .font(stackedLabelFont)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(label)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        Text(value)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                    }
                }
            }
            .padding(.vertical, 10)

            if !isLast {
                Divider()
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                copyToClipboard(value)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

private func copyToClipboard(_ string: String) {
#if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
#else
    UIPasteboard.general.string = string
#endif
}

// MARK: - Item Fields Section

struct ItemFieldsSection: View {
    let fields: [(FieldDefinition, FieldValue)]
    let layout: DetailLabelLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fields, id: \.0.id) { def, val in
                let isLast = def.id == fields.last?.0.id
                if def.isStatusField {
                    // The status field gets the same chip treatment as the item row, and
                    // resolves boolean statuses through their tab labels rather than showing
                    // a bare "Yes"/"No" that doesn't match what the tab bar says.
                    StatusFieldRowView(field: def, value: val, layout: layout, isLast: isLast)
                } else {
                    FieldRowView(label: def.name, value: val.displayValue(options: def.fieldOptions), layout: layout, isLast: isLast)
                }
            }
        }
    }
}

// MARK: - Status Field Row

private struct StatusFieldRowView: View {
    let field: FieldDefinition
    let value: FieldValue
    let layout: DetailLabelLayout
    var isLast: Bool = false

    /// Recomputed from the field value rather than read from `CatalogueItem.statusValue`,
    /// so the detail view shows what is actually stored on the item.
    private var storedValue: String {
        ItemFacetBuilder.statusValue(from: [value], definitions: [field])
    }

    @ViewBuilder
    private var chip: some View {
        if let label = field.statusLabel(for: storedValue) {
            FieldChipView(text: label, tint: field.statusChipTint(for: storedValue))
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }

    var body: some View {
        // Follows the field rows' layout so the card stays one table (or one stack); a lone
        // side-by-side chip row among stacked fields would read as a different component.
        Group {
            switch layout {
            case .beside:
                HStack {
                    Text(field.name)
                        .foregroundStyle(.secondary)
                    Spacer()
                    chip
                }
            case .above:
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    chip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
            }
        }
    }
}

// MARK: - Item Notes Section

/// Inside a card titled "Notes", so the text stands alone rather than under a second label.
/// Always present, even with nothing written: the placeholder and the pencil together say
/// "tap here to add some", which a card that only appears once notes exist can't.
struct ItemNotesSection: View {
    let notes: String?
    let onEdit: () -> Void

    private var hasNotes: Bool { !(notes ?? "").isEmpty }

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 12) {
                if let notes, hasNotes {
                    Text(notes)
                        .foregroundStyle(.primary)
                } else {
                    Text("Add notes…")
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasNotes ? "Notes" : "Add notes")
        .accessibilityValue(notes ?? "")
        .accessibilityHint("Edits the notes")
        .contextMenu {
            if let notes, hasNotes {
                Button {
                    copyToClipboard(notes)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}
