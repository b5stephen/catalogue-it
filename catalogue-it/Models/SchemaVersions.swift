//
//  SchemaVersions.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Schema Versions

/// The live model classes belong to the newest version; older versions keep frozen copies so
/// each change has a baseline to migrate from. For the next model change: add
/// `CatalogueSchemaV5` pointing at the live classes, turn this into a frozen copy of the V4
/// shape, and add a stage to `CatalogueMigrationPlan`.
///
/// Every version needs its CloudKit schema deployed to Production before the build ships —
/// see "Deploying the CloudKit schema" in CLAUDE.md.
enum CatalogueSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Catalogue.self,
            FieldDefinition.self,
            CatalogueItem.self,
            FieldValue.self,
            ItemPhoto.self,
        ]
    }
}

typealias CatalogueSchemaCurrent = CatalogueSchemaV4

// MARK: - Migration Plan

enum CatalogueMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CatalogueSchemaV1.self, CatalogueSchemaV2.self, CatalogueSchemaV3.self, CatalogueSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4]
    }

    /// Backfills the new `CatalogueItem.modifiedDate` from `createdDate`: the attribute default
    /// would stamp every existing item as edited at the moment of migration.
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: CatalogueSchemaV1.self,
        toVersion: CatalogueSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            // The frozen V2 class: the store is V2-shaped at this point, not the live shape.
            let items = try context.fetch(FetchDescriptor<CatalogueSchemaV2.CatalogueItem>())
            for item in items {
                item.modifiedDate = item.createdDate
            }
            try context.save()
        }
    )

    /// Adds `Catalogue.layoutOptionsData`; nil already means "all defaults", so nothing to backfill.
    static let v2ToV3 = MigrationStage.lightweight(
        fromVersion: CatalogueSchemaV2.self,
        toVersion: CatalogueSchemaV3.self
    )

    /// Adds `Catalogue.iconImageData` and `iconImageKind`; nil means the icon is `iconName`.
    static let v3ToV4 = MigrationStage.lightweight(
        fromVersion: CatalogueSchemaV3.self,
        toVersion: CatalogueSchemaV4.self
    )
}
