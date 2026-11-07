//
//  ExportSpreadsheetPreview.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Export Spreadsheet Preview

/// The header and first rows of the file as a table. The cells come from the same encoding as
/// the file, with line breaks flattened to fit a row.
struct ExportSpreadsheetPreview: View {
    let header: [String]?
    let rows: [[String]]
    let totalRows: Int

    private enum Layout {
        static let cellWidth: CGFloat = 130
        static let cornerRadius = AppConstants.CornerRadius.card
    }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    if let header {
                        row(header, background: Color(.tertiarySystemFill))
                            .fontWeight(.semibold)
                    }
                    ForEach(rows.indices, id: \.self) { index in
                        Divider()
                        row(rows[index], background: .clear)
                    }
                }
            }
            .font(.caption.monospaced())
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Layout.cornerRadius, style: .continuous))
            .clipShape(.rect(cornerRadius: Layout.cornerRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Spreadsheet preview")

            if totalRows > rows.count {
                Text("First \(rows.count) of \(totalRows) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func row(_ cells: [String], background: Color) -> some View {
        GridRow {
            ForEach(cells.indices, id: \.self) { index in
                Text(cells[index])
                    .lineLimit(1)
                    .frame(width: Layout.cellWidth, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(background, in: .rect)
            }
        }
    }
}
