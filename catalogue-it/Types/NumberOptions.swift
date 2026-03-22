//
//  NumberOptions.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 22/03/2026.
//

import Foundation

// MARK: - Number Options

/// Configuration options for a Number field.
struct NumberOptions: Codable, Equatable {
    var format: NumberFormat = .number
    var precision: Int = 0
}
