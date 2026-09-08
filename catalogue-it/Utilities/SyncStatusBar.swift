//
//  SyncStatusBar.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Sync Status Bar

/// Slim status strip pinned below the catalogue list, in the manner of Mail's
/// "Updated Just Now" line.
///
/// It renders nothing at all when idle — including when the user isn't signed into iCloud,
/// which is a deliberate choice rather than a fault. Progress is indeterminate because
/// CloudKit reports no record counts; the number shown is what has actually landed locally,
/// which is true without implying a total we can't know.
struct SyncStatusBar: View {
    let status: CloudKitSyncMonitor.Status
    var onShowError: () -> Void

    var body: some View {
        switch status {
        case .idle:
            EmptyView()

        case .syncing(.download, let itemCount):
            row {
                ProgressView()
                    .controlSize(.mini)
                Text("Syncing from iCloud · ^[\(itemCount) item](inflect: true)")
            }

        case .syncing(.upload, _):
            // No count going up: the local item total says nothing about how much is still
            // queued for upload, and showing it would imply progress we can't measure.
            row {
                ProgressView()
                    .controlSize(.mini)
                Text("Syncing to iCloud")
            }
            .foregroundStyle(.secondary)
            .transition(.opacity)

        case .failed:
            Button(action: onShowError) {
                row {
                    Image(systemName: "exclamationmark.icloud")
                    Text("iCloud sync paused · tap for details")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .transition(.opacity)
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .font(.footnote)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Preview

#Preview("Downloading") {
    SyncStatusBar(status: .syncing(direction: .download, itemCount: 1455), onShowError: {})
}

#Preview("Uploading") {
    SyncStatusBar(status: .syncing(direction: .upload, itemCount: 0), onShowError: {})
}

#Preview("Failed") {
    SyncStatusBar(status: .failed(message: "Your iCloud storage is full."), onShowError: {})
}
