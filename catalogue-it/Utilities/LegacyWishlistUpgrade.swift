//
//  LegacyWishlistUpgrade.swift
//  catalogue-it
//

import Foundation

// MARK: - Legacy Wishlist Upgrade

/// v1 export files carried wishlist as an `isWishlist` boolean on every item. Import
/// synthesises the "Status" option-list field a user would build by hand, with a value per item.
enum LegacyWishlistUpgrade {

    static let statusFieldName = "Status"
    static let ownedOption = "Owned"
    static let wishlistOption = "Wishlist"

    /// `nil` when the file already has a status field or no item carries the legacy flag.
    ///
    /// - Parameter fieldIDProvider: Injectable so tests can pin it.
    static func synthesisedStatusField(
        for dto: CatalogueDTO,
        fieldID: @autoclosure () -> UUID = UUID()
    ) -> FieldDefinitionDTO? {
        guard !dto.fieldDefinitions.contains(where: { $0.displayRole == .statusTabs }) else { return nil }
        guard dto.items.contains(where: { $0.isWishlist != nil }) else { return nil }

        let nextPriority = (dto.fieldDefinitions.map(\.priority).max() ?? -1) + 1
        return FieldDefinitionDTO(
            fieldID: fieldID(),
            name: uniqueName(among: dto.fieldDefinitions.map(\.name)),
            fieldType: .optionList,
            priority: nextPriority,
            fieldOptions: .optionList(OptionListOptions(
                options: [ownedOption, wishlistOption],
                defaultValue: ownedOption
            )),
            displayRole: .statusTabs
        )
    }

    /// Items with no legacy flag count as owned, the old default.
    static func statusFieldValue(for item: CatalogueItemDTO, fieldID: UUID) -> FieldValueDTO {
        FieldValueDTO(
            fieldDefinitionID: fieldID,
            fieldType: .optionList,
            textValue: (item.isWishlist ?? false) ? wishlistOption : ownedOption,
            numberValue: nil,
            dateValue: nil,
            boolValue: nil
        )
    }

    /// Avoids clashing with a user's own "Status" field under the editor's unique-name rule.
    private static func uniqueName(among existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(statusFieldName.lowercased()) else { return statusFieldName }
        var suffix = 2
        while taken.contains("\(statusFieldName) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(statusFieldName) \(suffix)"
    }
}
