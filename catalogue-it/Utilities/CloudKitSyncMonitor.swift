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

/// Tracks whether CloudKit is currently importing, and surfaces failures that the user can
/// actually act on.
///
/// SwiftData doesn't hand us the underlying `NSPersistentCloudKitContainer`, so its event
/// stream is read from `NSPersistentCloudKitContainer.eventChangedNotification` with
/// `object: nil` — the same approach `RemoteChangeObserver` uses for remote-change
/// notifications.
///
/// What the events can and cannot tell us: an `Event` carries only a type, start/end dates,
/// a success flag and an error. There is no record count and no percentage, so progress here
/// is necessarily indeterminate. The item count shown alongside it is counted from our own
/// store as rows land — honest about what has arrived, silent about what is still coming.
@MainActor
@Observable
final class CloudKitSyncMonitor {
    static let shared = CloudKitSyncMonitor()

    enum Direction: Equatable {
        /// Remote changes coming down. `itemCount` is meaningful here — rows are landing.
        case download
        /// Local changes going up. The local item count says nothing about how much is still
        /// queued, so it isn't shown for this direction.
        case upload
    }

    enum Status: Equatable {
        /// Nothing in flight, or CloudKit is simply not in use. Shows no UI.
        case idle
        /// A sync is running. `itemCount` is how many items exist locally so far.
        case syncing(direction: Direction, itemCount: Int)
        /// A failure the user may be able to resolve (storage full, throttling, schema).
        case failed(message: String)
    }

    private(set) var status: Status = .idle

    // `nonisolated` throughout this group: the build defaults declarations to @MainActor
    // (SWIFT_DEFAULT_ACTOR_ISOLATION), but the notification handler below runs on whatever
    // thread CloudKit posted from, before it hops to the main actor to update `status`.
    nonisolated private static let logger = Logger(subsystem: "catalogue-it", category: "CloudKitSyncMonitor")

    nonisolated private static func eventTypeName(_ type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup: "setup"
        case .import: "import"
        case .export: "export"
        @unknown default: "unknown(\(type.rawValue))"
        }
    }

    /// A large import arrives as a run of separate events rather than one long one, so the
    /// indicator is held briefly past the last one. Without this it strobes between batches.
    private static let quietPeriod = Duration.seconds(2)

    private var container: ModelContainer?
    private var observer: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    /// Tracked separately so a download, which carries a useful count, wins the label when
    /// both directions are in flight at once.
    private var inFlightDownloads = Set<UUID>()
    private var inFlightUploads = Set<UUID>()
    private var settleTask: Task<Void, Never>?

    /// Whether the device is signed into iCloud at all.
    ///
    /// This gate matters more than it looks: signed out, CloudKit still posts an import
    /// event that *starts and never finishes*, so without it the indicator would sit on
    /// "Syncing…" forever for anyone not using iCloud. Verified in the simulator.
    private var accountAvailable = false

    private init() {}

    // MARK: - Lifecycle

    /// Call once at app startup.
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

            // `.notice`, not `.debug`: debug-level entries live in a memory buffer and are
            // never written to the persistent log store, so they cannot be recovered from a
            // tester's device. Anything wanted back from TestFlight has to be notice or above,
            // and interpolations have to be marked public or they are redacted as <private>.
            Self.logger.notice("""
                CloudKit event: type=\(Self.eventTypeName(event.type), privacy: .public) \
                finished=\(finished, privacy: .public) succeeded=\(event.succeeded, privacy: .public)
                """)

            // Every failure is recorded, including the ones deliberately kept out of the UI
            // below. Staying quiet in the status bar about a self-resolving network error is a
            // separate decision from discarding the evidence.
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

    /// `CKContainer.default()` resolves to the container named in the entitlement, so the
    /// identifier still isn't repeated in Swift.
    private func refreshAccountStatus() async {
        let status = try? await CKContainer.default().accountStatus()
        accountAvailable = (status == .available)
        if !accountAvailable {
            inFlightDownloads.removeAll()
            inFlightUploads.removeAll()
            settleTask?.cancel()
            status.map { Self.logger.debug("iCloud account unavailable (status \($0.rawValue))") }
            self.status = .idle
        }
    }

    private func handle(id: UUID, direction: Direction, finished: Bool, failure: String?) {
        guard accountAvailable else { return }

        if let failure {
            // A real failure outranks any in-flight indicator — it needs to stay on screen.
            inFlightDownloads.removeAll()
            inFlightUploads.removeAll()
            settleTask?.cancel()
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
            settleTask?.cancel()
            updateSyncingStatus()
        }
    }

    private func updateSyncingStatus() {
        // A download is the more informative of the two, so it wins when both are running.
        let direction: Direction? = !inFlightDownloads.isEmpty ? .download
            : !inFlightUploads.isEmpty ? .upload
            : nil
        guard let direction else { return }
        status = .syncing(direction: direction, itemCount: currentItemCount())
    }

    /// Refreshes the count, then drops the indicator once nothing has been in flight for
    /// `quietPeriod`. Called by `RemoteChangeObserver` too, so the number climbs while rows land.
    func refreshCount() {
        guard case .syncing = status else { return }
        updateSyncingStatus()
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: Self.quietPeriod)
            guard !Task.isCancelled, inFlightDownloads.isEmpty, inFlightUploads.isEmpty else { return }
            if case .failed = status { return }
            status = .idle
        }
    }

    private func currentItemCount() -> Int {
        guard let context = container?.mainContext else { return 0 }
        let descriptor = FetchDescriptor<CatalogueItem>(predicate: #Predicate { $0.deletedDate == nil })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Error classification

    /// `nil` for conditions the user hasn't asked us to fix.
    ///
    /// Not being signed into iCloud is the important one: it is a deliberate choice, not a
    /// fault, and the app works fully without it. Nagging about it would be wrong.
    ///
    /// Classification runs over the *unwrapped* errors. `CKError.partialFailure` (code 2) is a
    /// container whose own code matches nothing here, so before this it fell through to
    /// `localizedDescription` and surfaced as "CKErrorDomain error 2" — including for the very
    /// conditions the list below exists to keep quiet, since an export's quota, network and
    /// throttling errors nearly always arrive wrapped.
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

        // Permanent rejections: a record CloudKit will refuse no matter how often it retries,
        // which is a stuck sync rather than a passing one. The user can't fix the cause, but
        // they can report it — the diagnostics screen behind this message is the point.
        // Ordered, not a Set: the code named in the message must be the same one on every
        // launch, or two testers hitting one bug file two different reports.
        let permanent: [CKError.Code] = [
            .invalidArguments, .serverRejectedRequest, .limitExceeded,
            .constraintViolation, .referenceViolation, .incompatibleVersion,
        ]
        if let stuck = permanent.first(where: codes.contains) {
            return String(
                localized: "Some changes were rejected by iCloud and won't upload (\(stuck.diagnosticName)). Tap for details you can send with beta feedback."
            )
        }

        // Everything left is the user's own choice or self-resolving, so it stays silent.
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

    /// Every CloudKit error code involved, the outer error's own plus each per-record error
    /// hiding in `CKPartialErrorsByItemIDKey`.
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
