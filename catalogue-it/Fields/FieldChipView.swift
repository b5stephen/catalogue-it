//
//  FieldChipView.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Chip View

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

/// Apart from `FieldDefinition` so previews of an unsaved draft tint exactly as the list will.
nonisolated enum StatusChipPalette {
    static let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]

    /// `nil` is an option no longer configured.
    static func tint(optionIndex index: Int?) -> Color {
        guard let index else { return .secondary }
        return colors[index % colors.count]
    }

    static func booleanTint(isTrue: Bool) -> Color {
        isTrue ? .green : .secondary
    }
}

extension FieldDefinition {
    /// From the option's position in the stored list, so it is the same on every device.
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

    /// Boolean statuses store tokens, not text.
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
