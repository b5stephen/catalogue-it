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

    /// What the type picker shows beneath the name.
    var pickerDescription: String {
        switch self {
        case .text:       String(localized: "Any words, e.g. Notes or Kit Number")
        case .number:     String(localized: "Amounts, years and prices")
        case .date:       String(localized: "A day, e.g. Acquired")
        case .boolean:    String(localized: "On or off, e.g. Built")
        case .optionList: String(localized: "One choice from a list you make")
        }
    }
}
