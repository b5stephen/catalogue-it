//
//  SchemaVersions.swift
//  catalogue-it
//

import Foundation
import SwiftData

// MARK: - Schema Versions

/// Pins the current model shape to an explicit version identifier.
///
/// SwiftData will happily infer a lightweight migration without any of this, so nothing here
/// changes behaviour today. It exists because enabling CloudKit means two app versions can
/// hold the same data at once, and the next model change needs a versioned baseline to
/// migrate *from* — reconstructing one after the fact is guesswork.
///
/// Only one version is declared deliberately. A real V1 → V2 stage requires a full copy of
/// every model class nested inside each version enum, and the app has not shipped: there is
/// no store in the wild at an older shape to migrate. When the first post-release model
/// change lands, add `CatalogueSchemaV2` (with its own copies of the models) and a
/// `.lightweight` stage between the two.
enum CatalogueSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

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

/// Migration plan for the store. No stages yet — see `CatalogueSchemaV1` for why.
enum CatalogueMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CatalogueSchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
