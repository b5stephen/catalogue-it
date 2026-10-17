//
//  SyncStatusBar.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Sync Status Bar

/// Text only, like Mail's "Updated Just Now": a full-width strip sat oddly in the iPad sidebar.
/// Renders nothing when idle or signed out of iCloud. The count is items landed during this
/// run, shown once there are some, which implies no total we can't know.
struct SyncStatusBar: View {
    let status: CloudKitSyncMonitor.Status
    var onShowError: () -> Void

    var body: some View {
        switch status {
        case .idle:
            EmptyView()

        case .syncing(.download, let newItemCount):
            row {
                ProgressView()
                    .controlSize(.mini)
                if newItemCount > 0 {
                    Text("Syncing from iCloud · ^[\(newItemCount) new item](inflect: true)")
                } else {
                    Text("Syncing from iCloud")
                }
            }

        case .syncing(.upload, _):
            // The local total says nothing about what is still queued.
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
    }
}

// MARK: - Preview

#Preview("Downloading") {
    SyncStatusBar(status: .syncing(direction: .download, newItemCount: 0), onShowError: {})
}

#Preview("Downloading new items") {
    SyncStatusBar(status: .syncing(direction: .download, newItemCount: 1455), onShowError: {})
}

#Preview("Uploading") {
    SyncStatusBar(status: .syncing(direction: .upload, newItemCount: 0), onShowError: {})
}

#Preview("Failed") {
    SyncStatusBar(status: .failed(message: "Your iCloud storage is full."), onShowError: {})
}
