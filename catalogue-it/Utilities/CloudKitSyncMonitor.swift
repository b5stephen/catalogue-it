//
//  CloudKitSyncMonitor.swift
//  catalogue-it
//

import CloudKit
import CoreData
import Foundation
import SwiftData
import os

// MARK: - CloudKit Sync Monitor

/// Read from `NSPersistentCloudKitContainer.eventChangedNotification` with `object: nil`,
/// since SwiftData doesn't expose the container. Events carry no record count or percentage,
/// so progress is indeterminate; the count shown is items landed in our store since the run
/// began — a delta, since every launch runs an incremental import that usually fetches nothing.
@MainActor
@Observable
final class CloudKitSyncMonitor {
    static let shared = CloudKitSyncMonitor()

    enum Direction: Equatable {
        case download
        /// No count: the local total says nothing about what is still queued.
        case upload
    }

    enum Status: Equatable {
        /// Also when CloudKit isn't in use.
        case idle
        /// `newItemCount` is zero for the routine incremental import every launch performs.
        case syncing(direction: Direction, newItemCount: Int)
        case failed(message: String)
    }

    private(set) var status: Status = .idle

    // `nonisolated`: the handler runs on whatever thread CloudKit posts from before hopping
    // to the main actor.
    nonisolated private static let logger = Logger(subsystem: "catalogue-it", category: "CloudKitSyncMonitor")

    nonisolated private static func eventTypeName(_ type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup: "setup"
        case .import: "import"
        case .export: "export"
        @unknown default: "unknown(\(type.rawValue))"
        }
    }

    /// A large import arrives as a run of separate events; without this the indicator strobes
    /// between them.
    private static let quietPeriod = Duration.seconds(2)

    /// Routine launch and foreground checks finish well inside this, so they don't flash the
    /// bar. Shorter on an empty store, a new device pulling everything down, where the bar is
    /// the only sign of life.
    private static let showDelayWhenEmpty = Duration.seconds(1)
    private static let showDelayWithCatalogues = Duration.seconds(3)

    private var container: ModelContainer?
    private var observer: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    /// So a download, which has a useful count, wins the label when both directions run.
    private var inFlightDownloads = Set<UUID>()
    private var inFlightUploads = Set<UUID>()
    private var settleTask: Task<Void, Never>?
    private var showTask: Task<Void, Never>?
    /// Spans idle to idle, quiet gaps included; `nil` between runs.
    private var runBaseline: Int?

    /// Signed out, CloudKit posts an import event that starts and never finishes, which would
    /// leave the indicator on "Syncing…" forever.
    private var accountAvailable = false

    private init() {}

    // MARK: - Lifecycle

    func start(container: ModelContainer) {
        guard observer == nil else { return }
        self.container = container

        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { _ in
            Task { @MainActor in await Self.shared.refreshAccountStatus() }
        }
        Task { await refreshAccountStatus() }

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { notification in
            // `Event` is not Sendable, so reduce it to plain values before hopping.
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }

            let id = event.identifier
            let direction: Direction = (event.type == .export) ? .upload : .download
            let finished = event.endDate != nil
            let failure = event.succeeded ? nil : event.error
            let message = Self.userFacingMessage(for: failure)

            // `.notice` and public: `.debug` entries are memory-only and can't be recovered from a
            // tester's device, and interpolations are otherwise redacted.
            Self.logger.notice("""
                CloudKit event: type=\(Self.eventTypeName(event.type), privacy: .public) \
                finished=\(finished, privacy: .public) succeeded=\(event.succeeded, privacy: .public)
                """)

            // Record every failure, including ones kept out of the UI below.
            if let failure {
                SyncDiagnostics.record(
                    SyncFailureReport(
                        error: failure,
                        eventType: Self.eventTypeName(event.type),
                        userFacingMessage: message
                    )
                )
            }

            Task { @MainActor in
                Self.shared.handle(id: id, direction: direction, finished: finished, failure: message)
            }
        }
    }

    // MARK: - Event handling

    /// Resolves to the entitlement's container, so the identifier isn't repeated in Swift.
    private func refreshAccountStatus() async {
        let status = try? await CKContainer.default().accountStatus()
        accountAvailable = (status == .available)
        if !accountAvailable {
            inFlightDownloads.removeAll()
            inFlightUploads.removeAll()
            endRun()
            status.map { Self.logger.debug("iCloud account unavailable (status \($0.rawValue))") }
            self.status = .idle
        }
    }

    private func handle(id: UUID, direction: Direction, finished: Bool, failure: String?) {
        guard accountAvailable else { return }

        if let failure {
            // A real failure outranks an in-flight indicator.
            inFlightDownloads.removeAll()
            inFlightUploads.removeAll()
            endRun()
            status = .failed(message: failure)
            Self.logger.error("CloudKit sync failed: \(failure, privacy: .public)")
            return
        }

        if finished {
            inFlightDownloads.remove(id)
            inFlightUploads.remove(id)
            scheduleSettle()
        } else {
            switch direction {
            case .download: inFlightDownloads.insert(id)
            case .upload: inFlightUploads.insert(id)
            }
            if runBaseline == nil { runBaseline = currentItemCount() }
            settleTask?.cancel()
            if case .syncing = status {
                updateSyncingStatus()
            } else {
                scheduleShow()
            }
        }
    }

    private func updateSyncingStatus() {
        let direction: Direction? = !inFlightDownloads.isEmpty ? .download
            : !inFlightUploads.isEmpty ? .upload
            : nil
        guard let direction else { return }
        let current = currentItemCount()
        // Deletions merging in during the run would otherwise read as negative.
        let arrived = max(0, current - (runBaseline ?? current))
        status = .syncing(direction: direction, newItemCount: arrived)
    }

    /// Called by `RemoteChangeObserver`, so the number climbs as rows land.
    func refreshCount() {
        guard case .syncing = status else { return }
        updateSyncingStatus()
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: Self.quietPeriod)
            guard !Task.isCancelled, inFlightDownloads.isEmpty, inFlightUploads.isEmpty else { return }
            endRun()
            if case .failed = status { return }
            status = .idle
        }
    }

    private func scheduleShow() {
        guard showTask == nil else { return }
        let delay = hasCatalogues() ? Self.showDelayWithCatalogues : Self.showDelayWhenEmpty
        showTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            showTask = nil
            // A no-op if the run already finished, the common case on launch.
            updateSyncingStatus()
        }
    }

    private func endRun() {
        settleTask?.cancel()
        showTask?.cancel()
        showTask = nil
        runBaseline = nil
    }

    private func hasCatalogues() -> Bool {
        guard let context = container?.mainContext else { return false }
        var descriptor = FetchDescriptor<Catalogue>(predicate: #Predicate { !$0.pendingDeletion })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    private func currentItemCount() -> Int {
        guard let context = container?.mainContext else { return 0 }
        let descriptor = FetchDescriptor<CatalogueItem>(predicate: #Predicate { $0.deletedDate == nil })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Error classification

    /// `nil` for conditions that aren't the user's to fix, including being signed out of iCloud,
    /// which is a choice. Classifies the *unwrapped* errors: `CKError.partialFailure` matches
    /// nothing itself, and quota, network and throttling errors nearly always arrive wrapped.
    nonisolated private static func userFacingMessage(for error: Error?) -> String? {
        guard let error else { return nil }
        let nsError = error as NSError

        // "Unable to initialize without an iCloud account (CKAccountStatusNoAccount)."
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 134400 { return nil }

        let codes = ckErrorCodes(in: error)
        guard !codes.isEmpty else { return error.localizedDescription }

        if codes.contains(.quotaExceeded) {
            return String(localized: "Your iCloud storage is full, so new changes can't be uploaded.")
        }

        // Permanent rejections: a stuck sync the user can't fix but can report. Ordered, not a
        // Set, so the code named in the message is the same on every launch.
        let permanent: [CKError.Code] = [
            .invalidArguments, .serverRejectedRequest, .limitExceeded,
            .constraintViolation, .referenceViolation, .incompatibleVersion,
        ]
        if let stuck = permanent.first(where: codes.contains) {
            return String(
                localized: "Some changes were rejected by iCloud and won't upload (\(stuck.diagnosticName)). Tap for details you can send with beta feedback."
            )
        }

        // The rest are the user's choice or self-resolving.
        let benign: Set<CKError.Code> = [
            .notAuthenticated, .managedAccountRestricted,
            .networkUnavailable, .networkFailure,
            .requestRateLimited, .zoneBusy, .serviceUnavailable,
            .serverResponseLost, .accountTemporarilyUnavailable,
            .operationCancelled, .changeTokenExpired, .serverRecordChanged,
        ]
        if codes.allSatisfy(benign.contains) { return nil }

        return error.localizedDescription
    }

    /// The outer error's code plus each per-record one in `CKPartialErrorsByItemIDKey`.
    nonisolated private static func ckErrorCodes(in error: Error) -> Set<CKError.Code> {
        var codes: Set<CKError.Code> = []
        if let ckError = error as? CKError { codes.insert(ckError.code) }

        if let map = (error as NSError).userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            codes.remove(.partialFailure)
            for inner in map.values {
                codes.formUnion(ckErrorCodes(in: inner))
            }
        }
        return codes
    }
}
