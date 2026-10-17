//
//  ItemDetailSections.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 16/03/2026.
//

import SwiftUI

// MARK: - Field Row

/// `.beside` keeps one table shape: a long value wraps trailing-aligned rather than changing
/// layout, and only a real block of text drops below its label. `.above` stacks every row, so
/// the label can drop to a caption.
private struct FieldRowView: View {
    let label: String
    let value: String
    let layout: DetailLabelLayout
    var isLast: Bool = false

    private var isBlockOfText: Bool {
        value.contains("\n") || value.count > 80
    }

    private var isStacked: Bool {
        layout == .above || isBlockOfText
    }

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
                    // Boolean statuses show their tab labels, not a bare "Yes"/"No".
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

    /// From the field value, not `statusValue`, so it shows what is actually stored.
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
        // Follows the field rows' layout so the card stays one table.
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

/// Always shown, even empty: the placeholder and pencil invite adding notes.
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
