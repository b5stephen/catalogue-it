//
//  FieldType.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import Foundation

// MARK: - Field Type

nonisolated enum FieldType: String, Codable, CaseIterable {
    case text = "Text"
    case number = "Number"
    case date = "Date"
    case boolean = "Yes/No"
    case optionList = "Option List"
}
