//
//  ExportFileName.swift
//  catalogue-it
//

import Foundation

// MARK: - Export File Name

/// `"<Catalogue>[ – <qualifier>] 2026-11-29 14.32.<ext>"`, so repeated exports don't overwrite
/// each other. The stamp is fixed-format rather than localised: year first sorts by date in
/// Finder and Files, and a localised date or time can contain `/` or `:`.
nonisolated enum ExportFileName {
    static func make(
        catalogueName: String,
        qualifier: String? = nil,
        exportedAt: Date,
        timeZone: TimeZone = .current,
        pathExtension: String
    ) -> String {
        let name = safe(catalogueName)
        let base = qualifier.map { "\(name) – \($0)" } ?? name
        return "\(base) \(stamp(exportedAt, timeZone: timeZone)).\(pathExtension)"
    }

    /// `/` separates paths, and `:` is shown as `/` by Finder.
    static func safe(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    /// Local wall-clock time, minutes only, with `.` between hour and minute.
    static func stamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d.%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0
        )
    }
}
