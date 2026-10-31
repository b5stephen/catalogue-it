//
//  FieldTypeTile.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Type Tile

/// Decorative: the row it sits in carries the accessibility label.
struct FieldTypeTile: View {
    let symbol: String
    let color: Color

    private static let size: CGFloat = 30

    init(_ fieldType: FieldType) {
        self.symbol = fieldType.icon
        self.color = fieldType.color
    }

    init(symbol: String, color: Color) {
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: Self.size, height: Self.size)
            .background(
                color.opacity(0.15),
                in: .rect(cornerRadius: AppConstants.CornerRadius.small, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
