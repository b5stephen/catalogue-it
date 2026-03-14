//
//  FieldType.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation
import SwiftUI

// MARK: - Field Type

/// The types of custom fields a user can add to a catalogue
enum FieldType: String, Codable, CaseIterable {
    case text = "Text"
    case number = "Number"
    case date = "Date"
    case boolean = "Yes/No"

    var icon: String {
        switch self {
        case .text: "textformat"
        case .number: "number"
        case .date: "calendar"
        case .boolean: "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .text: .blue
        case .number: .green
        case .date: .orange
        case .boolean: .purple
        }
    }
}
