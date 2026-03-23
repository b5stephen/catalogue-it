//
//  Catalogue+Color.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 23/03/2026.
//

import SwiftUI

extension Catalogue {
    /// The catalogue's accent color, derived from `colorHex`.
    var color: Color { Color(hex: colorHex) }
}
