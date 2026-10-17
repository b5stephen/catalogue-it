//
//  SyncDiagnosticsView.swift
//  catalogue-it
//

import SwiftData
import SwiftUI

// MARK: - Sync Diagnostics View

/// A screenshot is all TestFlight feedback carries, so this is shaped for one: monospaced,
/// compact, and with per-record errors collapsed by (code, record type). Nothing user-authored
/// appears — record ids are UUIDs and `CD_…` tokens are schema names — so it's safe to send.
struct SyncDiagnosticsView: View {
    /// `nil` when opened from the beta menu with nothing wrong.
    var headline: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var reports: [SyncFailureReport] = []
    @State private var largestFields: [String: Int] = [:]
    @State private var counts: [(String, Int)] = []
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let headline {
                        Text(headline)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }

                    section("BUILD") {
                        line("Version", BuildEnvironment.versionString)
                        line("CloudKit", BuildEnvironment.cloudKitEnvironment)
                        line("Captured", Self.timestamp.string(from: .now))
                    }

                    section("STORE") {
                        ForEach(counts, id: \.0) { name, count in
                            line(name, "\(count)")
                        }
                    }

                    section("OVERSIZED FIELDS") {
                        if largestFields.isEmpty {
                            // A negative result that matters: it rules out the per-record size limit.
                            Text("None ≥ \(SyncDiagnostics.fieldSizeThreshold / 1024) KB observed")
                                .font(Self.mono)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(largestFields.sorted(by: { $0.value > $1.value }), id: \.key) { name, bytes in
                                line(name, "\(bytes / 1024) KB max")
                            }
                        }
                    }

                    section("SYNC FAILURES") {
                        if reports.isEmpty {
                            Text("None recorded")
                                .font(Self.mono)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(reports) { report in
                                reportBlock(report)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .navigationTitle("Sync Diagnostics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                        copyToPasteboard()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Screenshot this screen and send it with TestFlight beta feedback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.bar)
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - Blocks

    @ViewBuilder
    private func reportBlock(_ report: SyncFailureReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Self.timestamp.string(from: report.date))  \(report.eventType)")
                .font(Self.mono.bold())
            Text(report.outerCode + (report.partialCount > 1 ? " · \(report.partialCount) records" : ""))
                .font(Self.mono)
                .foregroundStyle(.orange)

            ForEach(report.buckets) { bucket in
                Text("  \(bucket.count)× \(bucket.code) on \(bucket.recordType)")
                    .font(Self.mono)
                if !bucket.schemaTokens.isEmpty {
                    Text("    fields: \(bucket.schemaTokens.joined(separator: ", "))")
                        .font(Self.mono)
                        .foregroundStyle(.red)
                }
                if !bucket.sampleMessage.isEmpty {
                    Text("    \(bucket.sampleMessage)")
                        .font(Self.mono)
                        .foregroundStyle(.secondary)
                }
            }

            if report.userFacingMessage == nil {
                // Otherwise the screen seems to report failures the app hid on purpose.
                Text("  (not surfaced to the user — self-resolving or account state)")
                    .font(Self.mono)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)")
            .font(Self.mono)
    }

    private static let mono = Font.system(.caption, design: .monospaced)

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - Data

    private func reload() {
        reports = SyncDiagnostics.reports
        largestFields = SyncDiagnostics.largestFields
        counts = [
            ("Catalogues", count(for: Catalogue.self)),
            ("Items", count(for: CatalogueItem.self)),
            ("Field definitions", count(for: FieldDefinition.self)),
            ("Field values", count(for: FieldValue.self)),
            ("Photos", count(for: ItemPhoto.self)),
        ]
    }

    private func count<T: PersistentModel>(for _: T.Type) -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<T>())) ?? 0
    }

    // MARK: - Copy

    /// For the TestFlight comment box, which takes only text.
    private func plainText() -> String {
        var out = ["Catalogue-It sync diagnostics"]
        out.append("Version: \(BuildEnvironment.versionString)")
        out.append("CloudKit: \(BuildEnvironment.cloudKitEnvironment)")
        out.append("Captured: \(Self.timestamp.string(from: .now))")
        out.append("")
        out.append(counts.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
        out.append("")
        out.append("Oversized fields:")
        out.append(largestFields.isEmpty
            ? "  none ≥ \(SyncDiagnostics.fieldSizeThreshold / 1024) KB"
            : largestFields.sorted { $0.value > $1.value }.map { "  \($0.key): \($0.value) bytes" }.joined(separator: "\n"))
        out.append("")
        out.append("Failures:")
        if reports.isEmpty {
            out.append("  none recorded")
        }
        for report in reports {
            out.append("  [\(Self.timestamp.string(from: report.date))] \(report.eventType) — \(report.outerCode) · \(report.partialCount) record(s)")
            for bucket in report.buckets {
                out.append("    \(bucket.count)× \(bucket.code) on \(bucket.recordType)")
                if !bucket.schemaTokens.isEmpty {
                    out.append("      fields: \(bucket.schemaTokens.joined(separator: ", "))")
                }
                if !bucket.sampleMessage.isEmpty {
                    out.append("      \(bucket.sampleMessage)")
                }
            }
        }
        return out.joined(separator: "\n")
    }

    private func copyToPasteboard() {
        let text = plainText()
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        didCopy = true
    }
}

// MARK: - Preview

#Preview {
    SyncDiagnosticsView(headline: "Some changes were rejected by iCloud and won't upload.")
}
