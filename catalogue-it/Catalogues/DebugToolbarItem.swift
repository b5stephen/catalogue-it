//
//  DebugToolbarItem.swift
//  catalogue-it
//

#if DEBUG
import SwiftUI

struct DebugToolbarItem: ToolbarContent {
    var onLoadTestData: () -> Void
    var onRecalculateSortKeys: () -> Void
    var onValidateCloudKitSchema: () -> Void
    var onInitializeCloudKitSchema: () -> Void
    var onShowSyncDiagnostics: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Load Test Data", systemImage: "hammer") {
                    onLoadTestData()
                }
                Button("Recalculate Sort Keys", systemImage: "arrow.triangle.2.circlepath") {
                    onRecalculateSortKeys()
                }
                Divider()
                Button("Validate CloudKit Schema", systemImage: "checkmark.icloud") {
                    onValidateCloudKitSchema()
                }
                Button("Push CloudKit Schema (Dev)", systemImage: "icloud.and.arrow.up") {
                    onInitializeCloudKitSchema()
                }
                // Lives in this menu rather than its own toolbar slot in DEBUG builds: four
                // trailing items overflows behind a "…" on phone widths, and this menu is
                // already the home for developer affordances. TestFlight builds, which have no
                // hammer menu, get the standalone button instead — see ContentView.
                Button("Sync Diagnostics", systemImage: "stethoscope") {
                    onShowSyncDiagnostics()
                }
            } label: {
                Image(systemName: "hammer")
            }
        }
    }
}
#endif
