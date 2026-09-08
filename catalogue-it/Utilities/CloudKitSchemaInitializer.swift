//
//  CloudKitSchemaInitializer.swift
//  catalogue-it
//

#if DEBUG
import CloudKit
import CoreData
import SwiftData
import os

// MARK: - CloudKit Schema Initializer

/// Pushes the *complete* CloudKit schema for the model to the Development environment.
///
/// Why this is needed: `NSPersistentCloudKitContainer` grows the Development schema from the
/// records it actually exports, and a `CKRecord` carries no entry for a nil value. A field
/// nobody happened to populate while testing — an option-list's `fieldOptions` blob, a date
/// field's `dateValue`, a photo `caption` — therefore never enters the Development schema, so
/// it isn't in the snapshot that gets deployed to Production either. The first TestFlight user
/// to save one gets that record rejected, and the rejection arrives wrapped in a
/// `partialFailure` — "CKErrorDomain error 2".
///
/// `initializeCloudKitSchema` closes that hole by generating dummy records covering every
/// entity and every attribute in the managed object model, exporting them to create the
/// schema, then deleting them. Coverage comes from the model, not from what anyone remembered
/// to type in.
///
/// DEBUG-only, and deliberately so: it only has an effect against the Development environment,
/// and Apple documents it as a development-time tool rather than something an app ships with.
nonisolated enum CloudKitSchemaInitializer {

    private static let logger = Logger(subsystem: "catalogue-it", category: "CloudKitSchema")

    enum SchemaError: LocalizedError {
        case modelUnavailable
        case noContainerIdentifier

        var errorDescription: String? {
            switch self {
            case .modelUnavailable:
                "Couldn't build a managed object model from the SwiftData schema."
            case .noContainerIdentifier:
                "No iCloud container in the entitlement."
            }
        }
    }

    /// - Parameter dryRun: validates the model against CloudKit's rules and prints the schema
    ///   without uploading anything. Run this first — it is also how you get a printed schema
    ///   to compare against what CloudKit Console shows for Production.
    /// - Returns: A short summary for display.
    nonisolated static func run(dryRun: Bool) async throws -> String {
        // The same model list the app's container is built from, so coverage can't drift.
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: CatalogueSchemaV1.models) else {
            throw SchemaError.modelUnavailable
        }

        // `CKContainer.default()` resolves to the identifier in catalogue-it.entitlements, which
        // keeps the id out of Swift here the same way `cloudKitDatabase: .automatic` does in
        // catalogue_itApp — but NSPersistentCloudKitContainerOptions has no `.automatic`, so the
        // resolved value has to be passed through explicitly.
        guard let containerID = CKContainer.default().containerIdentifier else {
            throw SchemaError.noContainerIdentifier
        }

        let container = NSPersistentCloudKitContainer(name: "SchemaInit", managedObjectModel: model)

        // A throwaway store: the dummy records this generates must not land in the real one.
        let storeURL = URL.temporaryDirectory.appending(path: "schema-init-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerID
        )
        container.persistentStoreDescriptions = [description]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }

        defer {
            try? container.persistentStoreCoordinator.destroyPersistentStore(
                at: storeURL, type: .sqlite
            )
            try? FileManager.default.removeItem(at: storeURL)
        }

        // `.printSchema` dumps the full record-type/field listing to the console. That listing
        // is the thing to diff against CloudKit Console's Production schema.
        var options: NSPersistentCloudKitContainerSchemaInitializationOptions = [.printSchema]
        if dryRun { options.insert(.dryRun) }

        logger.notice("Initializing CloudKit schema for \(containerID, privacy: .public) (dryRun: \(dryRun, privacy: .public))")
        try container.initializeCloudKitSchema(options: options)
        logger.notice("CloudKit schema initialization finished")

        return dryRun
            ? "Schema validated and printed to the console. Nothing was uploaded."
            : "Schema uploaded to the Development environment for \(containerID).\n\nNow open CloudKit Console → Schema → Deploy Schema Changes to push it to Production."
    }
}
#endif
