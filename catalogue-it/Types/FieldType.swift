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
    case currency = "Currency"
    case date = "Date"
    case boolean = "Yes/No"

    var icon: String {
        switch self {
        case .text:     "textformat"
        case .number:   "number"
        case .currency: Self.currencyIcon
        case .date:     "calendar"
        case .boolean:  "checkmark.circle"
        }
    }

    /// Returns an SF Symbol name matching the device's locale currency, falling back to "dollarsign".
    private static var currencyIcon: String {
        switch Locale.current.currency?.identifier {
        case "EUR":        "eurosign"
        case "GBP":        "sterlingsign"
        case "JPY", "CNY": "yensign"
        case "INR":        "indianrupeesign"
        case "BRL":        "brazilianrealsign"
        case "KRW":        "wonsign"
        case "RUB":        "rublesign"
        case "TRY":        "turkishlirasign"
        case "CHF":        "francsign"
        case "UAH":        "hryvniasign"
        case "THB":        "bahtsign"
        case "NGN":        "nairasign"
        case "GEL":        "larisign"
        default:           "dollarsign"
        }
    }

    var color: Color {
        switch self {
        case .text:     .blue
        case .number:   .green
        case .currency: .teal
        case .date:     .orange
        case .boolean:  .purple
        }
    }
}
