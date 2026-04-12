//
//  FieldType.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation

// MARK: - Field Type

/// The types of custom fields a user can add to a catalogue
enum FieldType: String, Codable, CaseIterable {
    case text = "Text"
    case number = "Number"
    case date = "Date"
    case boolean = "Yes/No"
    case optionList = "Option List"
}
