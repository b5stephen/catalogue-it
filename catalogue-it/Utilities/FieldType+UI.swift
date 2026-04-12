//
//  FieldType+UI.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI

extension FieldType {
    var icon: String {
        switch self {
        case .text:       "textformat"
        case .number:     "number"
        case .date:       "calendar"
        case .boolean:    "checkmark.circle"
        case .optionList: "list.bullet"
        }
    }

    var color: Color {
        switch self {
        case .text:       .blue
        case .number:     .green
        case .date:       .orange
        case .boolean:    .purple
        case .optionList: .teal
        }
    }
}
