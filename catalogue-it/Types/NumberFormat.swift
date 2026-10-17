//
//  NumberFormat.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 22/03/2026.
//

import Foundation

// MARK: - Number Format

nonisolated enum NumberFormat: String, Codable, CaseIterable {
    case number = "Number"
    case currency = "Currency"
}
