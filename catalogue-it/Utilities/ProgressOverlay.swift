//
//  ProgressOverlay.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Progress Overlay

/// `total == 0` shows an indeterminate spinner with `preparingText`.
struct ProgressOverlay: View {
    let current: Int
    let total: Int
    var preparingText: String = "Preparing…"
    var processingText: (Int, Int) -> String = { current, total in "Processing \(current) of \(total) items…" }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if total > 0 {
                    ProgressView(value: Double(current), total: Double(total))
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                    Text(processingText(current, total))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text(preparingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
