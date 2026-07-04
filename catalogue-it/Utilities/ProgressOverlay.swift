//
//  ProgressOverlay.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Progress Overlay

/// Full-screen dimmed overlay showing indeterminate or determinate progress for a
/// long-running bulk operation (import, seed data generation, sort-key maintenance).
/// `total == 0` renders an indeterminate spinner with `preparingText`; otherwise a
/// linear progress bar with `current`/`total` formatted by `processingText`.
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
