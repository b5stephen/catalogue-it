//
//  LegacyWishlistUpgrade.swift
//  catalogue-it
//

import Foundation

// MARK: - Legacy Wishlist Upgrade

/// Converts pre-v2 export files, where wishlist membership was a hardcoded `isWishlist`
/// boolean on every item, into the current model where it is an ordinary `.statusTabs` field.
///
/// Export format v1 had no concept of display roles. Rather than dropping that data on
/// import, a "Status" option-list field is synthesised for the catalogue and each item gets
/// a field value derived from its old flag — producing exactly the configuration a user
/// would build by hand, with no data loss.
enum LegacyWishlistUpgrade {

    static let statusFieldName = "Status"
    static let ownedOption = "Owned"
    static let wishlistOption = "Wishlist"

    /// The status field to synthesise for a legacy catalogue, or `nil` when no upgrade
    /// is needed — either the file already defines a status field (v2+), or no item
    /// carries a legacy flag.
    ///
    /// - Parameter fieldIDProvider: Supplies the new field's `fieldID`. Injectable so
    ///   tests can pin it; defaults to a fresh UUID.
    static func synthesisedStatusField(
        for dto: CatalogueDTO,
        fieldID: @autoclosure () -> UUID = UUID()
    ) -> FieldDefinitionDTO? {
        // A file that already configures a status field is self-describing — leave it alone.
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

    /// The field value carrying an item's migrated status.
    /// Items with no legacy flag at all are treated as owned, matching the old default.
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

    /// Avoids colliding with a field the user already named "Status", which would trip
    /// the catalogue editor's unique-name rule on the next edit.
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
