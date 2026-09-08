//
//  SyncDiagnostics.swift
//  catalogue-it
//

import CloudKit
import Foundation
import Synchronization
import os

// Everything in this file is `nonisolated`: the build defaults declarations to @MainActor
// (SWIFT_DEFAULT_ACTOR_ISOLATION), but the CloudKit event notification is delivered on
// whatever thread posted it, and a failure report has to be built and recorded there.

// MARK: - Sync Failure Report

/// One CloudKit failure, unwrapped far enough to be actionable.
///
/// `CKError.partialFailure` (code 2) is a container, not a cause: the errors that matter are
/// in `userInfo[CKPartialErrorsByItemIDKey]`, one per rejected record. Everything the app
/// used to show came from `localizedDescription` on the *outer* error, which is why a failure
/// reached the user as the uninformative "CKErrorDomain error 2".
nonisolated struct SyncFailureReport: Codable, Identifiable, Equatable, Sendable {

    /// Per-record failures collapsed by (code, record type) so a 2000-item import produces a
    /// handful of lines rather than 2000. Screenshot legibility is the whole point.
    struct Bucket: Codable, Identifiable, Equatable, Sendable {
        var id: String { "\(code)|\(recordType)" }
        var code: String
        var recordType: String
        var count: Int
        /// First server message in this bucket, truncated. Carries the detail that names a
        /// missing field for schema errors.
        var sampleMessage: String
        /// `CD_…` tokens scraped from the server messages. For a schema-drift failure these
        /// name the exact fields missing from the deployed Production schema.
        var schemaTokens: [String]
    }

    var id: UUID = UUID()
    var date: Date = .now
    /// "import", "export" or "setup" — which direction was in flight.
    var eventType: String
    /// The outer error, e.g. "partialFailure (2)".
    var outerCode: String
    /// How many individual records the outer error wrapped.
    var partialCount: Int
    var buckets: [Bucket]
    /// The message the user was shown, or `nil` for failures deliberately kept silent
    /// (not signed in, offline, throttled). Silent failures are still recorded here.
    var userFacingMessage: String?
    var rawDescription: String
}

// MARK: - Build Environment

/// Which CloudKit environment this build talks to, and whether the beta-only diagnostics
/// entry point should exist.
nonisolated enum BuildEnvironment {

    /// TestFlight builds carry a `sandboxReceipt` rather than the App Store `receipt`.
    /// Debug builds count as beta so the screen is reachable while developing.
    ///
    /// `appStoreReceiptURL` is deprecated in favour of StoreKit's `AppTransaction.shared`,
    /// which is `async throws` — and this is read synchronously while building a toolbar, for
    /// a beta-only affordance where being wrong shows or hides one debug button. The
    /// deprecation warning is accepted rather than restructuring the call site around it.
    static var isBeta: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// Inferred, not read: there is no API that reports the mirroring environment. Debug
    /// builds sign into Development, everything else (TestFlight included) into Production.
    /// Labelled as inferred wherever it is shown, because that is what it is.
    static var cloudKitEnvironment: String {
        #if DEBUG
        return "Development (inferred)"
        #else
        return "Production (inferred)"
        #endif
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

// MARK: - Sync Diagnostics Store

/// Rolling record of sync failures and oversized field values, kept so the diagnostics screen
/// has something to show minutes after the fact — and across a relaunch.
///
/// Every failure lands here, including the ones `CloudKitSyncMonitor` deliberately keeps out
/// of the UI. Staying quiet about a self-resolving network error in the status bar is a
/// separate decision from throwing the evidence away.
nonisolated enum SyncDiagnostics {

    private static let logger = Logger(subsystem: "catalogue-it", category: "SyncDiagnostics")

    /// Reports beyond this are dropped oldest-first. Twenty covers a bulk import's worth of
    /// batches without turning the screen into a scroll marathon.
    private static let maxReports = 20

    /// Only field values at or above this size are recorded. A CloudKit record is capped at
    /// 1 MB in total, so anything under 8 KB is irrelevant and not worth taking a lock for on
    /// a path that runs once per field value per item.
    static let fieldSizeThreshold = 8 * 1024

    private struct State: Codable, Sendable {
        var reports: [SyncFailureReport] = []
        /// Largest observed value per instrumented field, keyed by field name.
        var largestFields: [String: Int] = [:]
    }

    private static let state = Mutex<State>(State())

    // MARK: Recording

    static func record(_ report: SyncFailureReport) {
        state.withLock {
            $0.reports.append(report)
            if $0.reports.count > maxReports {
                $0.reports.removeFirst($0.reports.count - maxReports)
            }
        }
        logger.error("""
            CloudKit \(report.eventType, privacy: .public) failed: \
            \(report.outerCode, privacy: .public) wrapping \(report.partialCount, privacy: .public) record error(s)
            """)
        for bucket in report.buckets {
            logger.error("""
                  ↳ \(bucket.count, privacy: .public)× \(bucket.code, privacy: .public) \
                on \(bucket.recordType, privacy: .public) \
                fields=\(bucket.schemaTokens.joined(separator: ","), privacy: .public) \
                — \(bucket.sampleMessage, privacy: .public)
                """)
        }
        persist()
    }

    /// Notes an oversized denormalised string so the record-size hypothesis can be confirmed
    /// or ruled out from the same screen. Threshold-gated: the comparison is free, the lock is
    /// only taken for the rare large value.
    static func noteFieldSize(_ name: String, _ length: Int) {
        guard length >= fieldSizeThreshold else { return }
        let isNewMax = state.withLock { s -> Bool in
            guard length > (s.largestFields[name] ?? 0) else { return false }
            s.largestFields[name] = length
            return true
        }
        guard isNewMax else { return }
        logger.notice("Oversized \(name, privacy: .public): \(length, privacy: .public) bytes")
    }

    // MARK: Reading

    static var reports: [SyncFailureReport] {
        state.withLock { $0.reports.reversed() }
    }

    static var largestFields: [String: Int] {
        state.withLock { $0.largestFields }
    }

    static func clear() {
        state.withLock { $0 = State() }
        try? FileManager.default.removeItem(at: storeURL)
    }

    // MARK: Persistence

    /// Survives a relaunch, which matters: a failed import is usually reported after the fact,
    /// often after the tester has force-quit the app.
    private static var storeURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        return base.appending(path: "sync-diagnostics.json")
    }

    static func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let loaded = try? JSONDecoder().decode(State.self, from: data) else { return }
        state.withLock { $0 = loaded }
    }

    private static func persist() {
        let snapshot = state.withLock { $0 }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

// MARK: - Error Unwrapping

nonisolated extension SyncFailureReport {

    /// Builds a report from a CloudKit mirroring error, descending into a partial failure to
    /// reach the per-record errors underneath.
    init(error: Error, eventType: String, userFacingMessage: String?) {
        let nsError = error as NSError
        let partials = Self.partialErrors(in: error)

        var order: [String] = []
        var byKey: [String: Bucket] = [:]
        for inner in partials {
            let bucket = Self.bucket(for: inner)
            if var existing = byKey[bucket.id] {
                existing.count += 1
                existing.schemaTokens = Array(Set(existing.schemaTokens + bucket.schemaTokens)).sorted()
                byKey[bucket.id] = existing
            } else {
                byKey[bucket.id] = bucket
                order.append(bucket.id)
            }
        }

        self.eventType = eventType
        self.outerCode = Self.describe(nsError)
        self.partialCount = partials.count
        self.buckets = order.compactMap { byKey[$0] }.sorted { $0.count > $1.count }
        self.userFacingMessage = userFacingMessage
        self.rawDescription = String(describing: nsError).prefix(2000).description
    }

    /// Flattens `CKPartialErrorsByItemIDKey`, one level of nesting deep — a partial failure
    /// occasionally wraps another. Returns `[error]` when there is nothing to unwrap, so a
    /// plain single error still produces one bucket.
    private static func partialErrors(in error: Error) -> [Error] {
        let userInfo = (error as NSError).userInfo
        guard let map = userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
              !map.isEmpty else { return [error] }
        return map.values.flatMap { inner -> [Error] in
            let nested = (inner as NSError).userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error]
            return (nested?.values).map(Array.init) ?? [inner]
        }
    }

    private static func bucket(for error: Error) -> Bucket {
        let nsError = error as NSError
        let message = nsError.localizedDescription
        let reason = (nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String) ?? ""
        let serverMessage = (nsError.userInfo["ServerErrorDescription"] as? String) ?? ""
        let combined = [message, reason, serverMessage].filter { !$0.isEmpty }.joined(separator: " · ")

        return Bucket(
            code: describe(nsError),
            recordType: recordType(for: error) ?? "unknown",
            count: 1,
            sampleMessage: String(combined.prefix(240)),
            schemaTokens: schemaTokens(in: combined)
        )
    }

    /// The CloudKit record type behind a failure, when the error carries a record at all.
    /// Core Data's mirrored types are named `CD_<Entity>`, which points straight at the model.
    private static func recordType(for error: Error) -> String? {
        guard let ckError = error as? CKError else { return nil }
        if let record = ckError.serverRecord ?? ckError.clientRecord {
            return record.recordType
        }
        return nil
    }

    /// Scrapes `CD_…` identifiers out of a server message. For the schema-drift case — a field
    /// present in Development but never deployed to Production — these name the exact fields
    /// CloudKit is rejecting, which is the single most useful thing in the whole report.
    private static func schemaTokens(in text: String) -> [String] {
        guard text.contains("CD_") else { return [] }
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted
        let tokens = text.components(separatedBy: separators)
        return Array(Set(tokens.filter { $0.hasPrefix("CD_") && $0.count > 3 })).sorted()
    }

    private static func describe(_ nsError: NSError) -> String {
        if nsError.domain == CKErrorDomain, let code = CKError.Code(rawValue: nsError.code) {
            return "\(code.diagnosticName) (\(nsError.code))"
        }
        return "\(nsError.domain) \(nsError.code)"
    }
}

// MARK: - CKError Naming

nonisolated extension CKError.Code {
    /// `CKError.Code` is not `CustomStringConvertible`, and the raw number is what leaves a
    /// tester staring at "error 2". Names are spelled out so a screenshot reads as English.
    var diagnosticName: String {
        switch self {
        case .internalError: "internalError"
        case .partialFailure: "partialFailure"
        case .networkUnavailable: "networkUnavailable"
        case .networkFailure: "networkFailure"
        case .badContainer: "badContainer"
        case .serviceUnavailable: "serviceUnavailable"
        case .requestRateLimited: "requestRateLimited"
        case .missingEntitlement: "missingEntitlement"
        case .notAuthenticated: "notAuthenticated"
        case .permissionFailure: "permissionFailure"
        case .unknownItem: "unknownItem"
        case .invalidArguments: "invalidArguments"
        case .resultsTruncated: "resultsTruncated"
        case .serverRecordChanged: "serverRecordChanged"
        case .serverRejectedRequest: "serverRejectedRequest"
        case .assetFileNotFound: "assetFileNotFound"
        case .assetFileModified: "assetFileModified"
        case .incompatibleVersion: "incompatibleVersion"
        case .constraintViolation: "constraintViolation"
        case .operationCancelled: "operationCancelled"
        case .changeTokenExpired: "changeTokenExpired"
        case .batchRequestFailed: "batchRequestFailed"
        case .zoneBusy: "zoneBusy"
        case .badDatabase: "badDatabase"
        case .quotaExceeded: "quotaExceeded"
        case .zoneNotFound: "zoneNotFound"
        case .limitExceeded: "limitExceeded"
        case .userDeletedZone: "userDeletedZone"
        case .tooManyParticipants: "tooManyParticipants"
        case .alreadyShared: "alreadyShared"
        case .referenceViolation: "referenceViolation"
        case .managedAccountRestricted: "managedAccountRestricted"
        case .participantMayNeedVerification: "participantMayNeedVerification"
        case .serverResponseLost: "serverResponseLost"
        case .assetNotAvailable: "assetNotAvailable"
        case .accountTemporarilyUnavailable: "accountTemporarilyUnavailable"
        // Plain `default`, not `@unknown default`: CloudKit adds codes, and a report that says
        // "code 42" is still useful — a compile error here would not be.
        default: "code \(rawValue)"
        }
    }
}
