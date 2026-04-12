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
        let schema = Schema([
            Catalogue.self,
            FieldDefinition.self,
            CatalogueItem.self,
            FieldValue.self,
            ItemPhoto.self,
        ])
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        ThumbnailLoader.shared = ThumbnailLoader(modelContainer: sharedModelContainer)

        // When running UI tests, force list layout so the test starts in a known state.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let layout = ProcessInfo.processInfo.environment["UITESTING_LAYOUT"] {
            UserDefaults.standard.set(layout, forKey: "itemLayoutStyle_ios")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { seedUITestDataIfNeeded() }
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

        let fieldDef = FieldDefinition(name: "Name", fieldType: .text, priority: 0)
        fieldDef.catalogue = catalogue
        ctx.insert(fieldDef)

        let item = CatalogueItem(isWishlist: false)
        item.catalogue = catalogue
        ctx.insert(item)

        let fieldValue = FieldValue(fieldDefinition: fieldDef, fieldType: .text)
        fieldValue.textValue = "Test Item"
        fieldValue.item = item
        ctx.insert(fieldValue)
    }
}
