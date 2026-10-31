//
//  FlagIconTile.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Flag Icon Tile

/// A flag's icon on a tinted tile, or a dashed "?" while it has none.
struct FlagIconTile: View {
    let icon: String?
    let color: Color?
    var size: CGFloat = 30

    private var radius: CGFloat { AppConstants.CornerRadius.small }

    var body: some View {
        if let icon {
            let tint = color ?? .accentColor
            Image(systemName: icon)
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(tint.opacity(0.15), in: .rect(cornerRadius: radius, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Text("?")
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
                .accessibilityHidden(true)
        }
    }
}
