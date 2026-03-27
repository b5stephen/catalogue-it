//
//  RecentlyDeletedView.swift
//  catalogue-it
//

import SwiftUI
import SwiftData

// MARK: - Recently Deleted View

struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let catalogue: Catalogue

    @Query private var deletedItems: [CatalogueItem]

    @State private var showingDeleteAllConfirmation = false

    init(catalogue: Catalogue) {
        self.catalogue = catalogue
        let targetID = catalogue.persistentModelID
        _deletedItems = Query(
            FetchDescriptor<CatalogueItem>(
                predicate: #Predicate { item in
                    item.catalogue?.persistentModelID == targetID
                        && item.deletedDate != nil
                },
                sortBy: [SortDescriptor(\.deletedDate, order: .reverse)]
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if deletedItems.isEmpty {
                    ContentUnavailableView(
                        "No Deleted Items",
                        systemImage: "trash",
                        description: Text("Items you delete are kept here for \(PurgeService.retentionDays) days before being permanently removed.")
                    )
                } else {
                    List {
                        ForEach(deletedItems) { item in
                            deletedItemRow(item)
                                .swipeActions(edge: .leading) {
                                    Button("Recover") {
                                        item.deletedDate = nil
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) {
                                        modelContext.delete(item)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Recently Deleted")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !deletedItems.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete All", role: .destructive) {
                            showingDeleteAllConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Permanently Delete All?",
                isPresented: $showingDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All \(deletedItems.count) Items", role: .destructive) {
                    for item in deletedItems { modelContext.delete(item) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("These items will be permanently removed and cannot be recovered.")
            }
        }
    }

    @ViewBuilder
    private func deletedItemRow(_ item: CatalogueItem) -> some View {
        let primaryValue = primaryValue(for: item)
        let daysLeft = daysUntilPurge(for: item)

        VStack(alignment: .leading, spacing: 4) {
            Text(primaryValue)
                .font(.headline)
            if let daysLeft {
                Text(daysLeft == 0 ? "Expires today" : "Expires in \(daysLeft) day\(daysLeft == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(daysLeft <= 3 ? Color.orange : Color.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func primaryValue(for item: CatalogueItem) -> String {
        guard let first = catalogue.fieldDefinitions
            .sorted(by: { $0.priority < $1.priority }).first,
              let fv = item.value(for: first),
              !fv.displayValue(options: first.fieldOptions).isEmpty
        else { return "Untitled Item" }
        return fv.displayValue(options: first.fieldOptions)
    }

    private func daysUntilPurge(for item: CatalogueItem) -> Int? {
        guard let deletedDate = item.deletedDate,
              let expiresAt = Calendar.current.date(
                byAdding: .day,
                value: PurgeService.retentionDays,
                to: deletedDate
              )
        else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date.now, to: expiresAt).day ?? 0
        return max(0, days)
    }
}
