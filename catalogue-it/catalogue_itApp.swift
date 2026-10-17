//
//  catalogue_itApp.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 20/02/2026.
//

import SwiftUI
import SwiftData

@main
struct catalogue_itApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: CatalogueSchemaCurrent.self)
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        // CloudKit can't back an in-memory store, so UI tests opt out. `.automatic` adopts the
        // entitlement's container, so the id isn't repeated here.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isUITesting,
            cloudKitDatabase: isUITesting ? .none : .automatic
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: CatalogueMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        ThumbnailLoader.container = sharedModelContainer
        BackgroundDeletionActor.container = sharedModelContainer
        SyncDiagnostics.load()
        RemoteChangeObserver.start(container: sharedModelContainer)
        CloudKitSyncMonitor.shared.start(container: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Before anything touches the store: an inner modifier's onAppear and `.task` bodies run
                // before an outer onAppear, and attaching after the backfill has written crashes its next
                // save — see ModelContextUndoModifier.
                .withModelContextUndoManager()
                .onAppear { seedUITestDataIfNeeded() }
                .task {
                    BackgroundDeletionActor.resumePendingDeletions()
                    await DerivedDataBackfill.runIfNeeded(in: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func seedUITestDataIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        let ctx = sharedModelContainer.mainContext
        guard (try? ctx.fetch(FetchDescriptor<Catalogue>()))?.isEmpty == true else { return }

        let catalogue = Catalogue(name: "Test Catalogue", iconName: "star", colorHex: "#007AFF")
        ctx.insert(catalogue)

        // A known layout, so UI tests start predictably.
        if let layoutRaw = ProcessInfo.processInfo.environment["UITESTING_LAYOUT"],
           let layout = ItemLayout(rawValue: layoutRaw) {
            catalogue.itemLayout = layout
        }

        let fieldDef = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        fieldDef.catalogue = catalogue
        ctx.insert(fieldDef)

        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)

        let fieldValue = FieldValue(fieldDefinition: fieldDef, fieldType: .text)
        fieldValue.textValue = "Test Item"
        fieldValue.item = item
        ctx.insert(fieldValue)

        // Saved now, so no change is pending when the undo manager is attached.
        try? ctx.save()
    }
}
