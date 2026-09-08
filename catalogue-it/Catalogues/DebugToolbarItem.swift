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
            } label: {
                Image(systemName: "hammer")
            }
        }
    }
}
#endif
