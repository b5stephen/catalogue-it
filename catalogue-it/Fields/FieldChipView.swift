//
//  FieldChipView.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Chip View

/// Compact coloured chip for an enum-like field value — used to render the status field
/// in item rows, cards, and the detail form, where a bare string wouldn't read as a state.
struct FieldChipView: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - Status Chip Colour

/// The chip colours a status field cycles through, and the rule that picks one.
///
/// Kept apart from `FieldDefinition` so the field-configuration previews — which work from
/// an unsaved draft — tint their sample chip exactly as the item list will.
///
/// `nonisolated` to match `statusChipTint(for:)`, which is called from wherever an item is
/// being rendered.
nonisolated enum StatusChipPalette {
    static let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]

    /// Colour for an option at `index` in the field's option list; `nil` (an option that is
    /// no longer configured) falls back to a neutral tint.
    static func tint(optionIndex index: Int?) -> Color {
        guard let index else { return .secondary }
        return colors[index % colors.count]
    }

    /// Colour for a Yes/No status: the "on" state is the only one that reads as a state.
    static func booleanTint(isTrue: Bool) -> Color {
        isTrue ? .green : .secondary
    }
}

extension FieldDefinition {
    /// A stable colour for a status value, derived from the value's position in the
    /// field's option list so the same option always gets the same chip colour —
    /// including across devices, since it depends only on stored configuration.
    func statusChipTint(for storedValue: String) -> Color {
        switch fieldType {
        case .optionList:
            let options = optionListOptions?.options ?? []
            return StatusChipPalette.tint(optionIndex: options.firstIndex(of: storedValue))
        case .boolean:
            return StatusChipPalette.booleanTint(isTrue: storedValue == ItemFacetBuilder.boolTrueToken)
        case .text, .number, .date:
            return .secondary
        }
    }

    /// The user-facing label for a stored status token. Boolean statuses store sentinels
    /// rather than text, so they resolve through `statusTabLabels`.
    func statusLabel(for storedValue: String) -> String? {
        guard !storedValue.isEmpty else { return nil }
        switch fieldType {
        case .optionList:
            return storedValue
        case .boolean:
            let labels = statusTabLabels
            return storedValue == ItemFacetBuilder.boolTrueToken ? labels.trueLabel : labels.falseLabel
        case .text, .number, .date:
            return nil
        }
    }
}
