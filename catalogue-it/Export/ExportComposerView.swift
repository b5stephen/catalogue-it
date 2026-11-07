//
//  ExportComposerView.swift
//  catalogue-it
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Export Composer

/// Everything the user chooses lives in this sheet's state and is gone when it closes.
struct ExportComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let catalogue: Catalogue
    let items: [CatalogueItem]

    @State private var format: ExportFormat
    @State private var ticked: Set<ExportColumn>

    @State private var attachesPhoto = true
    @State private var showsFieldNames = true
    @State private var leavesOutBlanks = true

    @State private var cardShape = ItemShareCardShape.square
    @State private var cardPhotoIndex: Int? = 0
    @State private var showsCatalogueName = true

    /// The photo the current format wants, downsampled once when the choice changes.
    @State private var photoImage: CGImage?

    @State private var pendingShare: [NSItemProvider]?
    @State private var didCopy = false

    init(catalogue: Catalogue, items: [CatalogueItem], format: ExportFormat = .message) {
        self.catalogue = catalogue
        self.items = items
        _format = State(initialValue: format)
        _ticked = State(initialValue: Set(format.columns(for: catalogue)))
    }

    // MARK: - Computed

    private var formats: [ExportFormat] {
        items.count == 1 ? [.message, .card] : [.message]
    }

    private var photos: [ItemPhoto] {
        guard items.count == 1 else { return [] }
        return items[0].photos.sorted { $0.priority < $1.priority }
    }

    private var wantedPhoto: ItemPhoto? {
        switch format {
        case .message: attachesPhoto ? photos.first : nil
        case .card: cardPhotoIndex.flatMap { photos.indices.contains($0) ? photos[$0] : nil }
        case .spreadsheet: nil
        }
    }

    private var columns: [ExportColumn] { format.columns(for: catalogue) }
    private var lockedColumn: ExportColumn? { format.lockedColumn(for: catalogue) }

    private var messageText: String {
        ItemShareText.text(
            for: items,
            in: catalogue,
            columns: ticked,
            options: ItemShareText.Options(showFieldNames: showsFieldNames, leaveOutBlanks: leavesOutBlanks)
        )
    }

    private var card: ItemShareCard? {
        guard items.count == 1 else { return nil }
        return ItemShareCard(
            item: items[0],
            in: catalogue,
            columns: ticked,
            photo: photoImage,
            shape: cardShape,
            showsCatalogueName: showsCatalogueName
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                form
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .task(id: wantedPhoto?.persistentModelID) { await loadPhoto() }
            .task(id: didCopy) {
                guard didCopy else { return }
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled { didCopy = false }
            }
            .sensoryFeedback(.success, trigger: didCopy) { _, copied in copied }
        }
    }

    // MARK: Preview and format

    private var header: some View {
        VStack(spacing: 12) {
            preview
                .frame(height: 240)
                .frame(maxWidth: .infinity)
            if formats.count > 1 {
                Picker("Format", selection: $format) {
                    ForEach(formats) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("exportFormatPicker")
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var preview: some View {
        switch format {
        case .message, .spreadsheet:
            ExportMessagePreview(text: messageText, photo: attachesPhoto ? photoImage : nil)
        case .card:
            if let card { ExportCardPreview(card: card) }
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section("Options") { options }
            fieldsSection
            Section("Item info") {
                ForEach(columns.filter { $0 == .notes }, id: \.self, content: fieldRow)
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        switch format {
        case .message, .spreadsheet:
            if !photos.isEmpty {
                Toggle("Attach first photo", isOn: $attachesPhoto)
            }
            Toggle("Show field names", isOn: $showsFieldNames)
            Toggle("Leave out blanks and No", isOn: $leavesOutBlanks)
        case .card:
            Picker("Shape", selection: $cardShape) {
                ForEach(ItemShareCardShape.allCases) { Text($0.title).tag($0) }
            }
            if !photos.isEmpty {
                Picker("Photo", selection: $cardPhotoIndex) {
                    Text("None").tag(Int?.none)
                    ForEach(photos.indices, id: \.self) { index in
                        Text("Photo \(index + 1)").tag(Int?.some(index))
                    }
                }
            }
            Toggle("Show catalogue name", isOn: $showsCatalogueName)
        }
    }

    private var fieldsSection: some View {
        Section {
            ForEach(columns.filter { $0 != .notes }, id: \.self, content: fieldRow)
        } header: {
            HStack {
                Text("Fields")
                Spacer()
                Button("All") { ticked = Set(columns) }
                Button("None") { ticked = Set(lockedColumn.map { [$0] } ?? []) }
            }
            .buttonStyle(.borderless)
            .textCase(nil)
        }
    }

    private func fieldRow(_ column: ExportColumn) -> some View {
        let isLocked = column == lockedColumn
        let isTicked = ticked.contains(column)
        return Button {
            if isTicked { ticked.remove(column) } else { ticked.insert(column) }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(column.title(in: catalogue))
                    if isLocked {
                        Text("Title")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isTicked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityAddTraits(isTicked ? .isSelected : [])
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                copy()
            } label: {
                Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("exportCopyButton")

            Button {
                pendingShare = itemProviders(forCopy: false)
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .background { ShareSheetAnchor(itemProviders: $pendingShare) }
            .accessibilityIdentifier("exportShareButton")
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func loadPhoto() async {
        guard let photo = wantedPhoto else {
            photoImage = nil
            return
        }
        let data = photo.imageData
        let image = await Task.detached { ItemShareCard.downsample(data) }.value
        if !Task.isCancelled { photoImage = image }
    }

    private func copy() {
        UIPasteboard.general.itemProviders = itemProviders(forCopy: true)
        didCopy = true
    }

    /// Rendered here, on demand, from the same card the preview shows.
    private func itemProviders(forCopy: Bool) -> [NSItemProvider] {
        switch format {
        case .message, .spreadsheet:
            var providers = [NSItemProvider(object: messageText as NSString)]
            if attachesPhoto, let photoImage {
                providers.append(NSItemProvider(object: UIImage(cgImage: photoImage)))
            }
            return providers
        case .card:
            guard let card, let png = ItemShareCardRenderer.pngData(for: card) else { return [] }
            if forCopy, let image = UIImage(data: png) {
                return [NSItemProvider(object: image)]
            }
            let provider = NSItemProvider()
            let name = Self.fileName(for: ItemShareText.title(for: items[0], in: catalogue))
            provider.register(ItemShareCardFile(pngData: png, filename: name))
            provider.suggestedName = name
            return [provider]
        }
    }

    private static func fileName(for title: String) -> String {
        title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".png"
    }
}
