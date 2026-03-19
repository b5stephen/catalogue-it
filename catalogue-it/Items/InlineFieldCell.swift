//
//  InlineFieldCell.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 19/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Inline Field Cell

/// Renders a read-only Text or a live editable control depending on isEditing.
/// Kept as a standalone view so bindings to SwiftData models are valid — @Bindable
/// cannot be declared inside a TableColumn @ViewBuilder closure.
struct InlineFieldCell: View {
    let item: CatalogueItem
    let field: FieldDefinition
    let isEditing: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var resolvedValue: FieldValue?
    @State private var numberText: String = ""

    var body: some View {
        Group {
            if isEditing, let fv = resolvedValue {
                switch fv.fieldType {
                case .text:
                    TextField("", text: Binding(
                        get: { fv.textValue ?? "" },
                        set: { fv.textValue = $0.isEmpty ? nil : $0 }
                    ))
                case .number:
                    TextField("", text: $numberText)
                        .onChange(of: numberText) { _, newValue in
                            fv.numberValue = Double(newValue)
                        }
                case .date:
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { fv.dateValue ?? .now },
                            set: { fv.dateValue = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                case .boolean:
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { fv.boolValue ?? false },
                            set: { fv.boolValue = $0 }
                        )
                    )
                    .labelsHidden()
                }
            } else {
                Text(item.value(for: field.name)?.displayValue ?? "")
                    .foregroundStyle(item.value(for: field.name) == nil ? .tertiary : .primary)
                    .lineLimit(1)
            }
        }
        .onAppear { resolve() }
        .onChange(of: isEditing) { _, editing in
            if editing { resolve() }
        }
    }

    private func resolve() {
        resolvedValue = item.value(for: field.name)
        if isEditing && resolvedValue == nil {
            let fv = FieldValue(fieldName: field.name, fieldType: field.fieldType, sortOrder: field.sortOrder)
            modelContext.insert(fv)
            fv.item = item
            resolvedValue = fv
        }
        if field.fieldType == .number {
            numberText = resolvedValue?.numberValue.map { String($0) } ?? ""
        }
    }
}

// MARK: - Wishlist Toggle Cell

/// Wraps item.isWishlist in a Toggle for edit mode, or shows the heart badge in read mode.
/// Separate view so @Bindable can be declared as a stored property.
struct WishlistToggleCell: View {
    @Bindable var item: CatalogueItem
    let isEditing: Bool

    var body: some View {
        if isEditing {
            Toggle("", isOn: $item.isWishlist)
                .labelsHidden()
        } else if item.isWishlist {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
                .accessibilityLabel("Wishlist")
        }
    }
}
