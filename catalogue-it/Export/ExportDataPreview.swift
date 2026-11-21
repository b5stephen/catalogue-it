//
//  ExportDataPreview.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Export Data Preview

/// The file as a document icon, with what it holds.
struct ExportDataPreview: View {
    let catalogueName: String
    let itemCount: Int
    /// `nil` while counting, and when photos are left out.
    let photoCount: Int?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 4) {
                Text(catalogueName)
                    .font(.headline)
                    .lineLimit(2)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let items = itemCount == 1 ? String(localized: "1 item") : String(localized: "\(itemCount) items")
        guard let photoCount else { return items }
        let photos = photoCount == 1 ? String(localized: "1 photo") : String(localized: "\(photoCount) photos")
        return items + " · " + photos
    }
}
