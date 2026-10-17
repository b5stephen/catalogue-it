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

/// Pushes the *complete* schema to Development. The container grows Development from records
/// it exports, and a `CKRecord` has no entry for a nil value, so a field nobody populated
/// while testing never reaches Production — and the first user to save one gets
/// "CKErrorDomain error 2". `initializeCloudKitSchema` covers every entity and attribute from
/// the model. DEBUG-only: it only affects Development.
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

    /// - Parameter dryRun: validates and prints the schema without uploading — the listing to
    ///   compare against Production in CloudKit Console.
    nonisolated static func run(dryRun: Bool) async throws -> String {
        // The app container's model list, so coverage can't drift.
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: CatalogueSchemaCurrent.models) else {
            throw SchemaError.modelUnavailable
        }

        // Resolves the entitlement's identifier, which the options type has no `.automatic` for.
        guard let containerID = CKContainer.default().containerIdentifier else {
            throw SchemaError.noContainerIdentifier
        }

        let container = NSPersistentCloudKitContainer(name: "SchemaInit", managedObjectModel: model)

        // Throwaway: the dummy records must not land in the real store.
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
