//
//  HasDetailColumnEnvironment.swift
//  catalogue-it
//

import SwiftUI

extension EnvironmentValues {
    /// Whether item detail is shown in a column beside the items, rather than pushed over
    /// them. `ContentView` sets it from the *window's* size class: the leading column of a
    /// split view is narrow enough to report `.compact` on its own, which is exactly the case
    /// where the detail column is right there next to it — so a view asking its own size class
    /// would push a second copy of the detail onto the stack.
    @Entry var hasDetailColumn: Bool = true
}
