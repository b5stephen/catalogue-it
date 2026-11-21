//
//  ToolbarContent+Overflow.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Toolbar Overflow Priority

/// On iOS 27 a crowded toolbar moves items into a trailing overflow menu, lowest priority
/// first. Earlier versions have no priorities, so these leave the item as it is.
extension ToolbarContent {
    @ToolbarContentBuilder
    func overflowsLast() -> some ToolbarContent {
        if #available(iOS 27, *) {
            visibilityPriority(.high)
        } else {
            self
        }
    }

    @ToolbarContentBuilder
    func overflowsFirst() -> some ToolbarContent {
        if #available(iOS 27, *) {
            visibilityPriority(.low)
        } else {
            self
        }
    }
}
