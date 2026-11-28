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
    @Environment(\.modelContext) private var modelContext

    let catalogue: Catalogue
    /// Set when opened from the toolbar with a filter active, which adds the Items picker.
    let filters: ExportFilters?

    /// `ids` is what the spreadsheet exports, in row order, and can be far larger than the
    /// `items` loaded for the preview and the Message and Card formats.
    @State private var export: ExportItems
    @State private var scope = ExportScope.filtered
    @State private var filteredCount: Int
    @State private var scopeTask: Task<Void, Never>?
    @State private var showsScopeProgress = false

    @State private var format: ExportFormat
    @State private var ticked: Set<ExportColumn>
    /// The last format with columns, whose ticks a format after Data carries on from.
    @State private var tickedFormat: ExportFormat

    @State private var attachesPhoto = true
    @State private var showsFieldNames = true
    @State private var leavesOutBlanks = true

    @State private var cardShape = ItemShareCardShape.square
    @State private var cardPhotoIndex: Int? = 0
    @State private var showsCatalogueName = true

    @State private var spreadsheetOptions = SpreadsheetEncoding.Options()
    @State private var includesPhotos = true
    @State private var photoCount: Int?
    @State private var exportProgress: (done: Int, total: Int)?
    @State private var showsExportProgress = false
    @State private var exportTask: Task<Void, Never>?
    @State private var exportFailed = false

    /// The photo the current format wants, downsampled once when the choice changes.
    @State private var photoImage: CGImage?

    @State private var pendingShare: ShareSheetContent?
    @State private var didCopy = false

    private static let previewRowLimit = 5

    init(catalogue: Catalogue, export: ExportItems, format: ExportFormat, filters: ExportFilters? = nil) {
        self.catalogue = catalogue
        self.filters = filters
        _export = State(initialValue: export)
        _filteredCount = State(initialValue: export.ids.count)
        _format = State(initialValue: format)
        _tickedFormat = State(initialValue: format)
        _ticked = State(initialValue: Set(format.columns(for: catalogue)))
    }

    init(catalogue: Catalogue, request: ExportRequest) {
        self.init(catalogue: catalogue, export: request.export, format: request.format, filters: request.filters)
    }

    /// One item, opening on Message.
    init(catalogue: Catalogue, item: CatalogueItem) {
        self.init(catalogue: catalogue, export: ExportItems(items: [item]), format: .message)
    }

    // MARK: - Computed

    private var items: [CatalogueItem] { export.items }
    private var exportIDs: [PersistentIdentifier] { export.ids }

    private var formats: [ExportFormat] { ExportFormat.available(forItemCount: exportIDs.count) }

    private var photos: [ItemPhoto] {
        guard items.count == 1 else { return [] }
        return items[0].photos.sorted { $0.priority < $1.priority }
    }

    private var wantedPhoto: ItemPhoto? {
        switch format {
        case .message: attachesPhoto ? photos.first : nil
        case .card: cardPhotoIndex.flatMap { photos.indices.contains($0) ? photos[$0] : nil }
        case .spreadsheet, .data: nil
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

    private var spreadsheetRequest: SpreadsheetRequest {
        SpreadsheetRequest(
            catalogueID: catalogue.persistentModelID,
            itemIDs: exportIDs,
            columns: columns.filter(ticked.contains),
            options: spreadsheetOptions,
            filtered: filters != nil && scope == .filtered
        )
    }

    private var isExporting: Bool { exportTask != nil }

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
            .onChange(of: format) { _, new in
                carryTicks(to: new)
                // A Data export is usually a backup, which a filter in force would quietly cut short.
                if new == .data, filters != nil { scope = .all }
            }
            .task(id: PhotoCountKey(ids: exportIDs, isData: format == .data)) { await countPhotos() }
            .onChange(of: scope) { _, new in loadScope(new) }
            .onDisappear {
                exportTask?.cancel()
                scopeTask?.cancel()
            }
            .overlay {
                if showsScopeProgress {
                    ProgressOverlay(current: 0, total: 0, preparingText: "Preparing items…")
                } else if showsExportProgress, let progress = exportProgress {
                    ProgressOverlay(
                        current: progress.done,
                        total: progress.total,
                        preparingText: "Preparing export…",
                        processingText: { current, total in "Exporting \(current) of \(total) items…" }
                    )
                }
            }
            .alert("Couldn't Create File", isPresented: $exportFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(format == .data ? "The file couldn't be created. Try again." : "The spreadsheet couldn't be created. Try again.")
            }
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
            Picker("Format", selection: $format) {
                ForEach(formats) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("exportFormatPicker")
            .padding(.horizontal)
            if exportIDs.count > ExportFormat.messageItemLimit {
                Text("Messages are limited to \(ExportFormat.messageItemLimit) items.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let filters {
                scopePicker(filters)
            }
        }
        .padding(.vertical, 12)
    }

    private func scopePicker(_ filters: ExportFilters) -> some View {
        HStack {
            Text("Items")
                .foregroundStyle(.secondary)
            Picker("Items", selection: $scope) {
                Text("Filtered · \(filteredCount)").tag(ExportScope.filtered)
                Text("All · \(filters.allCount)").tag(ExportScope.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Items")
            .accessibilityIdentifier("exportScopePicker")
            .disabled(scopeTask != nil)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var preview: some View {
        switch format {
        case .message:
            ExportMessagePreview(text: messageText, photo: attachesPhoto ? photoImage : nil)
        case .spreadsheet:
            spreadsheetPreview
        case .card:
            if let card { ExportCardPreview(card: card) }
        case .data:
            ExportDataPreview(
                catalogueName: catalogue.name,
                itemCount: exportIDs.count,
                photoCount: includesPhotos ? photoCount : nil
            )
        }
    }

    private var spreadsheetPreview: some View {
        let resolved = SpreadsheetEncoding.columns(columns.filter(ticked.contains), in: catalogue.fieldDefinitions)
        let style = spreadsheetOptions.valueStyle
        let rows = items.prefix(Self.previewRowLimit).map { item in
            SpreadsheetEncoding.cells(for: item, columns: resolved, photoCount: item.photos.count, style: style)
                .map(SpreadsheetEncoding.tsvCell)
        }
        return ExportSpreadsheetPreview(
            header: spreadsheetOptions.includesHeader ? SpreadsheetEncoding.headerCells(for: resolved) : nil,
            rows: rows,
            totalRows: exportIDs.count
        )
    }

    // MARK: Form

    private var form: some View {
        Form {
            if format == .data {
                Section {
                    Toggle("Include photos", isOn: $includesPhotos)
                } footer: {
                    Text("Everything about these items, with the catalogue's fields and settings. Open the file in Catalogue-It to add them as a new catalogue.")
                }
            } else {
                Section("Options") { options }
                fieldsSection
                Section("Item info") {
                    ForEach(columns.filter(\.isItemInfo), id: \.self, content: fieldRow)
                }
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        switch format {
        case .message:
            if !photos.isEmpty {
                Toggle("Attach first photo", isOn: $attachesPhoto)
            }
            if items.count == 1 {
                Toggle("Show field names", isOn: $showsFieldNames)
            }
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
        case .spreadsheet:
            Picker("Values", selection: $spreadsheetOptions.valueStyle) {
                ForEach(SpreadsheetEncoding.ValueStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Header row", isOn: $spreadsheetOptions.includesHeader)
        case .data:
            EmptyView()
        }
    }

    private var fieldsSection: some View {
        Section {
            ForEach(columns.filter { !$0.isItemInfo }, id: \.self, content: fieldRow)
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
            // A file of photos is no use on the pasteboard.
            if format != .data {
                Button {
                    copy()
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("exportCopyButton")
                .disabled(isExporting)
            }

            Button {
                share()
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .background { ShareSheetAnchor(content: $pendingShare) }
            .accessibilityIdentifier("exportShareButton")
            .disabled(isExporting)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Resolves the new scope's IDs off the main thread. The overlay appears only if that is
    /// still running after ~500ms.
    private func loadScope(_ scope: ExportScope) {
        guard let filters else { return }
        let container = modelContext.container
        let context = modelContext
        scopeTask = Task {
            let overlayDelay = Task {
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { showsScopeProgress = true }
            }
            let ids = try? await filters.selection(for: scope).resolve(in: container, current: filters.fingerprint)
            overlayDelay.cancel()
            showsScopeProgress = false
            scopeTask = nil
            guard !Task.isCancelled, let ids else { return }
            export = ExportItems(ids: ids, in: context)
            if scope == .filtered { filteredCount = ids.count }
            if !formats.contains(format) { format = .spreadsheet }
        }
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

    private func countPhotos() async {
        guard format == .data else { return }
        let ids = exportIDs
        let container = modelContext.container
        photoCount = nil
        let count = try? await Task.detached {
            try await DataFileWriter(modelContainer: container).photoCount(itemIDs: ids)
        }.value
        if !Task.isCancelled { photoCount = count }
    }

    private func copy() {
        if format == .spreadsheet {
            let request = spreadsheetRequest
            runExport(
                { container, progress in
                    try await SpreadsheetWriter(modelContainer: container).tsv(request, onProgress: progress)
                },
                then: { text in
                    UIPasteboard.general.string = text
                    didCopy = true
                }
            )
            return
        }
        UIPasteboard.general.itemProviders = itemProviders(forCopy: true)
        didCopy = true
    }

    private func share() {
        switch format {
        case .spreadsheet:
            let request = spreadsheetRequest
            runExport(
                { container, progress in
                    try await SpreadsheetWriter(modelContainer: container).writeCSV(request, onProgress: progress)
                },
                then: { url in pendingShare = .file(url) }
            )
            return
        case .data:
            let request = DataFileRequest(
                catalogueID: catalogue.persistentModelID,
                itemIDs: exportIDs,
                includesPhotos: includesPhotos
            )
            runExport(
                { container, progress in
                    try await DataFileWriter(modelContainer: container).write(request, onProgress: progress)
                },
                then: { url in pendingShare = .file(url) }
            )
            return
        case .message, .card:
            break
        }
        pendingShare = .itemProviders(itemProviders(forCopy: false))
    }

    /// Runs `work` off the main thread, where it makes its own writer from the container. The
    /// progress overlay appears only if it is still running after ~500ms.
    private func runExport<Result: Sendable>(
        _ work: @escaping @Sendable (ModelContainer, @escaping SpreadsheetWriter.Progress) async throws -> Result,
        then finish: @escaping (Result) -> Void
    ) {
        let container = modelContext.container
        exportProgress = (done: 0, total: 0)
        exportTask = Task {
            let overlayDelay = Task {
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { showsExportProgress = true }
            }
            let (updates, continuation) = AsyncStream.makeStream(of: (Int, Int).self, bufferingPolicy: .bufferingNewest(1))
            let watcher = Task {
                for await (done, total) in updates { exportProgress = (done: done, total: total) }
            }

            let task = Task.detached {
                try await work(container) { done, total in continuation.yield((done, total)) }
            }
            let result = await withTaskCancellationHandler {
                await task.result
            } onCancel: {
                task.cancel()
            }

            continuation.finish()
            watcher.cancel()
            overlayDelay.cancel()
            showsExportProgress = false
            exportProgress = nil
            exportTask = nil
            switch result {
            case .success(let value): finish(value)
            case .failure(let error): if !(error is CancellationError) { exportFailed = true }
            }
        }
    }

    /// Ticks stay for the columns both formats share; columns only the new format offers start
    /// ticked, as every column does. Data has no columns, so it carries nothing and the next
    /// format picks up from the one before it.
    private func carryTicks(to new: ExportFormat) {
        guard new != .data else { return }
        let old = tickedFormat
        tickedFormat = new
        let oldColumns = Set(old.columns(for: catalogue))
        var carried = Set(new.columns(for: catalogue).filter { ticked.contains($0) || !oldColumns.contains($0) })
        if let locked = new.lockedColumn(for: catalogue) { carried.insert(locked) }
        ticked = carried
    }

    /// Rendered here, on demand, from the same card the preview shows.
    private func itemProviders(forCopy: Bool) -> [NSItemProvider] {
        switch format {
        case .spreadsheet, .data:
            return []
        case .message:
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
        ExportFileName.safe(title) + ".png"
    }
}

// MARK: - Photo Count Key

private struct PhotoCountKey: Equatable {
    let ids: [PersistentIdentifier]
    let isData: Bool
}

// MARK: - Value Style Titles

private extension SpreadsheetEncoding.ValueStyle {
    var title: LocalizedStringKey {
        switch self {
        case .forSpreadsheet: "For spreadsheets"
        case .asShown: "As shown in app"
        }
    }
}
