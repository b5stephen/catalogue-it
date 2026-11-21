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
                // Here rather than its own slot: four trailing items overflow on phone widths. TestFlight
                // builds, which have no hammer menu, get a standalone button — see ContentView.
                Button("Sync Diagnostics", systemImage: "stethoscope") {
                    onShowSyncDiagnostics()
                }
            } label: {
                Label("Developer", systemImage: "hammer")
            }
        }
        .overflowsFirst()
    }
}
#endif
