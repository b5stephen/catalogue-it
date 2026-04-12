//
//  DebugToolbarItem.swift
//  catalogue-it

#if DEBUG
import SwiftUI

struct DebugToolbarItem: ToolbarContent {
    var onTap: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Load Test Data", systemImage: "hammer") {
                onTap()
            }
        }
    }
}
#endif
