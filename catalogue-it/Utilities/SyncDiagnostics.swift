//
//  SyncDiagnostics.swift
//  catalogue-it
//

import CloudKit
import Foundation
import StoreKit
import Synchronization
import os

// All `nonisolated`: CloudKit event notifications arrive on whatever thread posted them, and
// the report is built and recorded there.

// MARK: - Sync Failure Report

/// `CKError.partialFailure` (code 2) is a container, not a cause: the per-record errors are in
/// `userInfo[CKPartialErrorsByItemIDKey]`.
nonisolated struct SyncFailureReport: Codable, Identifiable, Equatable, Sendable {

    /// Collapsed by (code, record type), so a 2000-item import fits in a screenshot.
    struct Bucket: Codable, Identifiable, Equatable, Sendable {
        var id: String { "\(code)|\(recordType)" }
        var code: String
        var recordType: String
        var count: Int
        /// Truncated. For schema errors it names the missing field.
        var sampleMessage: String
        /// For schema drift, the fields missing from the deployed Production schema.
        var schemaTokens: [String]
    }

    var id: UUID = UUID()
    var date: Date = .now
    var eventType: String
    /// e.g. "partialFailure (2)".
    var outerCode: String
    var partialCount: Int
    var buckets: [Bucket]
    /// `nil` for failures deliberately kept silent, which are still recorded.
    var userFacingMessage: String?
    var rawDescription: String
}

// MARK: - Build Environment

nonisolated enum BuildEnvironment {

    /// TestFlight runs against StoreKit's sandbox. Debug builds count as beta. Anything short of a
    /// verified sandbox transaction counts as not beta: being wrong only shows or hides a button.
    static func isBeta() async -> Bool {
        #if DEBUG
        return true
        #else
        guard case .verified(let transaction) = try? await AppTransaction.shared else { return false }
        return transaction.environment == .sandbox
        #endif
    }

    /// Inferred — no API reports the mirroring environment — and labelled so wherever shown.
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

/// Rolling and persisted, so the diagnostics screen has something to show after the fact.
/// Records every failure, including those kept out of the UI.
nonisolated enum SyncDiagnostics {

    private static let logger = Logger(subsystem: "catalogue-it", category: "SyncDiagnostics")

    private static let maxReports = 20

    /// A record is capped at 1 MB, so smaller values don't justify the lock on a path that runs
    /// per field value.
    static let fieldSizeThreshold = 8 * 1024

    private struct State: Codable, Sendable {
        var reports: [SyncFailureReport] = []
        /// Keyed by field name.
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

    /// To confirm or rule out the record-size hypothesis from the same screen.
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

    /// A failed import is usually reported after the tester has force-quit the app.
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

    /// One level deep: a partial failure occasionally wraps another.
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

    /// Mirrored types are named `CD_<Entity>`.
    private static func recordType(for error: Error) -> String? {
        guard let ckError = error as? CKError else { return nil }
        if let record = ckError.serverRecord ?? ckError.clientRecord {
            return record.recordType
        }
        return nil
    }

    /// For schema drift these name the exact fields CloudKit is rejecting.
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
    /// So a screenshot reads as English rather than "error 2".
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
        // Not `@unknown default`: CloudKit adds codes, and "code 42" is still useful.
        default: "code \(rawValue)"
        }
    }
}
