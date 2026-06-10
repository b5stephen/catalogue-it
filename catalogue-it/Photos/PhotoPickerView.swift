//
//  PhotoPickerView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI
import PhotosUI

// MARK: - Photo Picker View

/// A Form Section component that manages photo selection and display for an item.
@MainActor
struct PhotoPickerView: View {
    @Binding var photos: [PhotoDraft]
    @Binding var previewPhotoID: UUID?

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos: Bool = false
    @State private var loadError: Error? = nil
    @State private var loadTask: Task<Void, Never>?
    @State private var isEditingPhotos: Bool
    #if os(iOS)
    @State private var isCameraPresented = false
    @State private var cameraCoordinator: CameraCoordinator?
    #endif

    init(photos: Binding<[PhotoDraft]>, previewPhotoID: Binding<UUID?>, startEditing: Bool = false) {
        self._photos = photos
        self._previewPhotoID = previewPhotoID
        self._isEditingPhotos = State(initialValue: startEditing)
    }

    var body: some View {
        let loading = isLoadingPhotos
        Section {
            if isEditingPhotos {
                List {
                    ForEach($photos) { $photo in
                        PhotoListRow(photo: $photo)
                            .listRowInsets(EdgeInsets(top: 11, leading: 0, bottom: 11, trailing: 0))
                    }
                    .onMove { from, to in
                        photos.move(fromOffsets: from, toOffset: to)
                        for index in photos.indices { photos[index].priority = index }
                    }
                    .onDelete { offsets in
                        offsets.forEach { deletePhoto(id: photos[$0].id) }
                    }
                }
                .environment(\.editMode, .constant(.active))
                .frame(height: CGFloat(photos.count) * PhotoListRow.rowHeight + 4)
                .scrollDisabled(true)
                .listStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                PhotoGridView(
                    photos: $photos,
                    onTap: { id in previewPhotoID = id }
                )
            }

            if !isEditingPhotos {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    Label(
                        loading ? "Loading…" : "Add Photos",
                        systemImage: loading ? "hourglass" : "photo.badge.plus"
                    )
                }
                .disabled(isLoadingPhotos)
                .onChange(of: selectedItems) {
                    loadPhotos()
                }
                #if os(iOS)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { isCameraPresented = true } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .disabled(isLoadingPhotos)
                }
                #endif
            }
        } header: {
            HStack {
                Text("Photos")
                Spacer()
                if !photos.isEmpty {
                    Button(isEditingPhotos ? "Done" : "Edit") {
                        withAnimation(.spring(duration: 0.2)) {
                            isEditingPhotos.toggle()
                        }
                    }
                    .font(.subheadline)
                    .textCase(nil)
                }
            }
        }
        .onChange(of: photos.isEmpty) { _, isEmpty in
            if isEmpty { isEditingPhotos = false }
        }
        .alert("Couldn't Load Photo", isPresented: Binding<Bool>(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError?.localizedDescription ?? "")
        }
        #if os(iOS)
        .onChange(of: isCameraPresented) { _, newValue in
            guard newValue else { return }
            let coordinator = CameraCoordinator(
                onCapture: { image in appendCapturedPhoto(image) },
                onDismiss: { isCameraPresented = false; cameraCoordinator = nil }
            )
            cameraCoordinator = coordinator
            coordinator.present()
        }
        #endif
    }

    // MARK: - Helpers

    private func loadPhotos() {
        guard !selectedItems.isEmpty else { return }
        loadTask?.cancel()
        isLoadingPhotos = true

        loadTask = Task {
            var newDrafts: [PhotoDraft] = []
            let startOrder = photos.count

            for (index, item) in selectedItems.enumerated() {
                guard !Task.isCancelled else { break }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let compressed = data.compressedAsJPEG(quality: 0.8) else { continue }
                    newDrafts.append(PhotoDraft(imageData: compressed, priority: startOrder + index))
                } catch {
                    if !(error is CancellationError) { loadError = error }
                }
            }

            guard !Task.isCancelled else { return }
            photos.append(contentsOf: newDrafts)
            selectedItems = []
            isLoadingPhotos = false
        }
    }

    #if os(iOS)
    private func appendCapturedPhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        photos.append(PhotoDraft(imageData: data, priority: photos.count))
    }
    #endif

    private func deletePhoto(id: UUID) {
        withAnimation {
            photos.removeAll { $0.id == id }
            for index in photos.indices {
                photos[index].priority = index
            }
        }
    }
}

// MARK: - Photo Grid View

@MainActor
private struct PhotoGridView: View {
    @Binding var photos: [PhotoDraft]
    let onTap: (UUID) -> Void

    private let cellSize = AppConstants.ThumbnailSize.photoPicker
    private let spacing: CGFloat = 12

    var body: some View {
        if !photos.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cellSize), spacing: spacing)],
                spacing: spacing
            ) {
                ForEach($photos) { $photo in
                    PhotoThumbnailView(photo: $photo)
                        .onTapGesture { onTap(photo.id) }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Photo Thumbnail View

private struct PhotoThumbnailView: View {
    @Binding var photo: PhotoDraft

    var body: some View {
        if let image = photo.imageData.asImage() {
            image
                .resizable()
                .scaledToFill()
                .frame(
                    width: AppConstants.ThumbnailSize.photoPicker,
                    height: AppConstants.ThumbnailSize.photoPicker
                )
                .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.small))
                .contentShape(.rect)
        }
    }
}

// MARK: - Photo List Row

private struct PhotoListRow: View {
    static let contentHeight: CGFloat = 44
    static let rowHeight: CGFloat = contentHeight + 22  // 11pt top inset + 11pt bottom inset

    @Binding var photo: PhotoDraft

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 4)
            if let image = photo.imageData.asImage() {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.contentHeight, height: Self.contentHeight)
                    .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.small))
            }
            TextField("Caption (optional)", text: $photo.caption)
                .foregroundStyle(photo.caption.isEmpty ? .secondary : .primary)
            Spacer()
        }
        .frame(height: Self.contentHeight)
    }
}

// MARK: - Photo Edit Detail Sheet

struct PhotoEditDetailSheet: View {
    @Binding var draft: PhotoDraft
    let totalCount: Int
    let position: Int
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image = draft.imageData.asImage() {
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.medium))
                    }

                    TextField("Caption (optional)", text: $draft.caption)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle(totalCount > 1 ? "Photo \(position) of \(totalCount)" : "Photo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    Form {
        PhotoPickerView(photos: .constant([]), previewPhotoID: .constant(nil))
    }
}

#if os(iOS)
#Preview("Edit Mode") {
    struct Container: View {
        @State var photos: [PhotoDraft] = {
            func makePhoto(_ color: UIColor, priority: Int) -> PhotoDraft {
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
                let data = renderer.jpegData(withCompressionQuality: 0.8) { ctx in
                    color.setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
                }
                return PhotoDraft(imageData: data, priority: priority)
            }
            return [
                makePhoto(.systemBlue, priority: 0),
                makePhoto(.systemRed, priority: 1),
                makePhoto(.systemGreen, priority: 2),
            ]
        }()

        var body: some View {
            Form { PhotoPickerView(photos: $photos, previewPhotoID: .constant(nil), startEditing: true) }
        }
    }
    return Container()
}
#endif
