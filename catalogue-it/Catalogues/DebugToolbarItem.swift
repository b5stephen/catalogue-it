//
//  DebugToolbarItem.swift
//  catalogue-it
//

#if DEBUG
import SwiftUI

struct DebugToolbarItem: ToolbarContent {
    var onLoadTestData: () -> Void
    var onRecalculateSortKeys: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Load Test Data", systemImage: "hammer") {
                    onLoadTestData()
                }
                Button("Recalculate Sort Keys", systemImage: "arrow.triangle.2.circlepath") {
                    onRecalculateSortKeys()
                }
            } label: {
                Image(systemName: "hammer")
            }
        }
    }
}
#endif
