//
//  ExportMessagePreview.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Export Message Preview

/// The text as a sent message, with the attached photo above it.
struct ExportMessagePreview: View {
    let text: String
    let photo: CGImage?

    private enum Layout {
        static let bubbleCornerRadius: CGFloat = 20
        static let photoCornerRadius = AppConstants.CornerRadius.card
        static let photoHeight: CGFloat = 100
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 6) {
                if let photo {
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Layout.photoHeight * CGFloat(photo.width) / CGFloat(photo.height), height: Layout.photoHeight)
                        .clipShape(.rect(cornerRadius: Layout.photoCornerRadius, style: .continuous))
                }
                Text(text)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.tint, in: .rect(cornerRadius: Layout.bubbleCornerRadius, style: .continuous))
                    .textSelection(.disabled)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Message preview")
    }
}
