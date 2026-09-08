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
        // Model list lives on the versioned schema so it stays in one place; see SchemaVersions.swift.
        let schema = Schema(versionedSchema: CatalogueSchemaV1.self)
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        // CloudKit is not a valid combination with an in-memory store, so UI-test runs opt out.
        // Otherwise `.automatic` adopts the container named in catalogue-it.entitlements — the
        // container id is deliberately not repeated here.
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
        RemoteChangeObserver.start(container: sharedModelContainer)
        CloudKitSyncMonitor.shared.start(container: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { seedUITestDataIfNeeded() }
                .task { BackgroundDeletionActor.resumePendingDeletions() }
                .withModelContextUndoManager()
        }
        .modelContainer(sharedModelContainer)
    }

    private func seedUITestDataIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        let ctx = sharedModelContainer.mainContext
        guard (try? ctx.fetch(FetchDescriptor<Catalogue>()))?.isEmpty == true else { return }

        let catalogue = Catalogue(name: "Test Catalogue", iconName: "star", colorHex: "#007AFF")
        ctx.insert(catalogue)

        // Force a known layout so the UI test starts in a predictable state.
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
    }
}
