//
//  HasDetailColumnEnvironment.swift
//  catalogue-it
//

import SwiftUI

extension EnvironmentValues {
    /// Set from the *window's* size class: the leading column reports `.compact` on its own
    /// exactly when the detail column sits beside it.
    @Entry var hasDetailColumn: Bool = true
}
