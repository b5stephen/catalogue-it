//
//  SyncStatusBarModifier.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Sync Status Bar Modifier

/// Pins `SyncStatusBar` below the content and wires up its error alert.
///
/// Applied to the catalogue list only. Two attempts to put it elsewhere were dropped: an
/// inset on the `NavigationSplitView` doesn't reach columns pushed onto their own stack in
/// compact width, and on the item screen iOS 26 renders `.searchable` as a bottom bar that
/// occupies the same edge. The catalogue list is also where a user waits on a sync, so it is
/// the screen that needs it.
private struct SyncStatusBarModifier: ViewModifier {
    @State private var showingError = false

    func body(content: Content) -> some View {
        let status = CloudKitSyncMonitor.shared.status

        content
            .safeAreaInset(edge: .bottom) {
                SyncStatusBar(status: status) { showingError = true }
                    .animation(.default, value: status)
            }
            .alert("iCloud Sync Problem", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                if case .failed(let message) = status {
                    Text(message)
                }
            }
    }
}

extension View {
    /// Shows the CloudKit sync indicator below this view. Renders nothing while idle.
    func cloudSyncStatusBar() -> some View {
        modifier(SyncStatusBarModifier())
    }
}
