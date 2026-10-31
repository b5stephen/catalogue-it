//
//  FieldBadge.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Field Badge

/// A small tinted capsule tag shown beside a field or option name.
struct FieldBadge: View {
    let title: String
    let systemImage: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(tint.opacity(0.15), in: .capsule)
        .fixedSize()
    }
}
