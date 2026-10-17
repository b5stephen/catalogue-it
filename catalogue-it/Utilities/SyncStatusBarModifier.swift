//
//  SyncStatusBarModifier.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Sync Status Bar Modifier

/// On the catalogue list only: a split-view inset doesn't reach columns pushed onto their own
/// stack in compact width, and on the item screen iOS 26 puts `.searchable` on the same edge.
private struct SyncStatusBarModifier: ViewModifier {
    @State private var showingError = false

    func body(content: Content) -> some View {
        let status = CloudKitSyncMonitor.shared.status

        content
            .safeAreaInset(edge: .bottom) {
                SyncStatusBar(status: status) { showingError = true }
                    .animation(.default, value: status)
            }
            .sheet(isPresented: $showingError) {
                // A sheet: an alert can't carry the per-record detail.
                SyncDiagnosticsView(headline: {
                    if case .failed(let message) = status { return message }
                    return nil
                }())
            }
    }
}

extension View {
    /// Renders nothing while idle.
    func cloudSyncStatusBar() -> some View {
        modifier(SyncStatusBarModifier())
    }
}
