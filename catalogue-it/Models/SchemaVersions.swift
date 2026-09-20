//
//  SchemaVersions.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Schema Versions

/// Pins the current model shape to an explicit version identifier.
///
/// SwiftData would infer a lightweight migration without any of this, but enabling CloudKit
/// means two app versions can hold the same data at once, and each model change needs a
/// versioned baseline to migrate *from* — reconstructing one after the fact is guesswork.
///
/// The live model classes always belong to the newest version. Older versions keep frozen
/// copies of theirs (see `CatalogueSchemaV1`, `CatalogueSchemaV2`), so the process for the
/// next model change is: add `CatalogueSchemaV4` pointing at the live classes, turn this enum
/// into a frozen copy of the V3 shape, and add a stage between the two to
/// `CatalogueMigrationPlan`.
///
/// Every version listed here also needs its CloudKit schema deployed to Production before
/// the build ships — see "Deploying the CloudKit schema" in CLAUDE.md.
enum CatalogueSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

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

/// The version the app opens its store with.
typealias CatalogueSchemaCurrent = CatalogueSchemaV3

// MARK: - Migration Plan

enum CatalogueMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CatalogueSchemaV1.self, CatalogueSchemaV2.self, CatalogueSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3]
    }

    /// V2 adds `CatalogueItem.modifiedDate`. The column itself is a lightweight addition; the
    /// custom stage exists to backfill it. The attribute default would stamp every existing
    /// item with the moment of migration, which reads as "everything was edited today". An
    /// item nobody has edited since it was created should say so: `modifiedDate == createdDate`.
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: CatalogueSchemaV1.self,
        toVersion: CatalogueSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            // The frozen V2 class, not the live one: this stage runs against a V2-shaped
            // store, before any later stage has brought it up to the live shape.
            let items = try context.fetch(FetchDescriptor<CatalogueSchemaV2.CatalogueItem>())
            for item in items {
                item.modifiedDate = item.createdDate
            }
            try context.save()
        }
    )

    /// V3 adds `Catalogue.layoutOptionsData`, the one column that carries every per-catalogue
    /// layout option from here on (see `CatalogueLayoutOptions`). Optional, and nil already
    /// means "all defaults", so there is nothing to backfill.
    static let v2ToV3 = MigrationStage.lightweight(
        fromVersion: CatalogueSchemaV2.self,
        toVersion: CatalogueSchemaV3.self
    )
}
