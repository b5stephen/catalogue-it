//
//  FieldDefinitionDraft.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import Foundation

// MARK: - Field Definition Draft

/// A lightweight, non-persisted representation of a field definition used during catalogue editing.
struct FieldDefinitionDraft: Identifiable {
    let id = UUID()
    var name: String
    var fieldType: FieldType
    var sortOrder: Int
}
