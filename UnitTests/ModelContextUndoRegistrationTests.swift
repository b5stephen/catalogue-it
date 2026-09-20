//
//  ModelContextUndoRegistrationTests.swift
//  UnitTests
//

import Testing
import Foundation
import SwiftData
@testable import catalogue_it

// MARK: - Model Context Undo Registration Tests

/// Covers the gate every `undoManager` assignment goes through. SwiftData crashes a save
/// that registers undo for a model changed while no undo manager was attached ("A snapshot
/// should exist before creating a new snapshot for undo" — the TestFlight 0.6.0 (5) launch
/// crash). These tests run the sequences that produced it and the ones the gate must keep
/// working; a regression here is a crashed test process, not a failed expectation.
@MainActor
struct ModelContextUndoRegistrationTests {

    /// Holds the container: `mainContext` doesn't retain it, and a released container resets
    /// its context and destroys every model loaded through it.
    @MainActor private struct Fixture {
        let container: ModelContainer
        var ctx: ModelContext { container.mainContext }
        let item: CatalogueItem
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Catalogue.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = container.mainContext
        let catalogue = Catalogue(name: "Test")
        ctx.insert(catalogue)
        let item = CatalogueItem()
        item.catalogue = catalogue
        ctx.insert(item)
        try ctx.save()
        return Fixture(container: container, item: item)
    }

    @Test("The launch race: undo attached during a suspended sweep takes effect only after it")
    func attachDuringSuspensionIsDeferred() async throws {
        let fixture = try makeFixture()
        let (ctx, item) = (fixture.ctx, fixture.item)
        let undoManager = UndoManager()

        // Nothing attached yet, as at launch before the undo modifier's onAppear.
        await ctx.withUndoRegistrationSuspended {
            item.searchText = "first chunk"
            await Task.yield()
            // onAppear fires mid-sweep.
            ctx.setDesiredUndoManager(undoManager)
            #expect(ctx.undoManager == nil)
            item.searchText = "second chunk"
            try? ctx.save()   // crashed in 0.6.0 (5)
        }

        #expect(ctx.undoManager === undoManager)
        #expect(!ctx.hasChanges)
        item.searchText = "user edit"
        try ctx.save()
        #expect(undoManager.canUndo)
    }

    @Test("Suspension detaches an already-attached manager and restores it afterwards")
    func suspensionRestoresAttachedManager() throws {
        let fixture = try makeFixture()
        let (ctx, item) = (fixture.ctx, fixture.item)
        let undoManager = UndoManager()
        ctx.setDesiredUndoManager(undoManager)
        #expect(ctx.undoManager === undoManager)

        ctx.withUndoRegistrationSuspended {
            #expect(ctx.undoManager == nil)
            item.searchText = "derived"
            try? ctx.save()
        }

        #expect(ctx.undoManager === undoManager)
        #expect(!undoManager.canUndo)
    }

    @Test("Changes left pending by a suspended body are saved before undo is re-attached")
    func pendingChangesSavedBeforeReattach() async throws {
        let fixture = try makeFixture()
        let (ctx, item) = (fixture.ctx, fixture.item)
        let undoManager = UndoManager()
        ctx.setDesiredUndoManager(undoManager)

        await ctx.withUndoRegistrationSuspended {
            item.searchText = "edited during an await, never saved by the body"
            await Task.yield()
        }

        #expect(!ctx.hasChanges)
        #expect(ctx.undoManager === undoManager)
        item.searchText = "after"
        try ctx.save()   // would crash had the pending change survived the re-attach
    }

    @Test("Nested suspensions re-attach only when the outermost ends")
    func nestedSuspensions() throws {
        let fixture = try makeFixture()
        let (ctx, item) = (fixture.ctx, fixture.item)
        let undoManager = UndoManager()
        ctx.setDesiredUndoManager(undoManager)

        ctx.withUndoRegistrationSuspended {
            ctx.withUndoRegistrationSuspended {
                item.searchText = "inner"
            }
            #expect(ctx.undoManager == nil)
            item.searchText = "outer"
            try? ctx.save()
        }
        #expect(ctx.undoManager === undoManager)
    }

    @Test("Detaching through the gate while suspended sticks after the suspension")
    func detachDuringSuspension() throws {
        let fixture = try makeFixture()
        let ctx = fixture.ctx
        ctx.setDesiredUndoManager(UndoManager())
        ctx.withUndoRegistrationSuspended {
            ctx.setDesiredUndoManager(nil)
        }
        #expect(ctx.undoManager == nil)
    }
}
