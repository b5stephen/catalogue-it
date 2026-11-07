//
//  ExportCardPreview.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Export Card Preview

/// The card itself, laid out at full size and scaled down to the width it is given.
struct ExportCardPreview: View {
    let card: ItemShareCard

    private static let cornerRadius = AppConstants.CornerRadius.medium

    var body: some View {
        let size = card.shape.size
        Color.clear
            .aspectRatio(size, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    card
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
            .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Card preview")
    }
}
