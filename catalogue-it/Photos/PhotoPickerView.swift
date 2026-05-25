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

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos: Bool = false
    @State private var loadError: Error? = nil
    @State private var loadTask: Task<Void, Never>?
    @State private var isEditingPhotos = false
    @State private var pendingDeleteId: UUID? = nil
    @State private var previewDraft: PhotoDraft? = nil
    #if os(iOS)
    @State private var isCameraPresented = false
    @State private var cameraCoordinator: CameraCoordinator?
    #endif

    var body: some View {
        let loading = isLoadingPhotos
        Section {
            if isEditingPhotos {
                ForEach($photos) { $photo in
                    PhotoListRow(photo: $photo)
                }
                .onMove { from, to in
                    photos.move(fromOffsets: from, toOffset: to)
                    for index in photos.indices { photos[index].priority = index }
                }
                .onDelete { offsets in
                    offsets.forEach { pendingDeleteId = photos[$0].id }
                }
            } else {
                PhotoGridView(
                    photos: $photos,
                    onTap: { id in
                        guard let draft = photos.first(where: { $0.id == id }) else { return }
                        previewDraft = draft
                    }
                )
            }

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
        .environment(\.editMode, .constant(isEditingPhotos ? .active : .inactive))
        .onChange(of: photos.isEmpty) { _, isEmpty in
            if isEmpty { isEditingPhotos = false }
        }
        .confirmationDialog(
            "Delete Photo?",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = pendingDeleteId {
                Button("Delete Photo", role: .destructive) {
                    deletePhoto(id: id)
                }
            }
        }
        .sheet(item: $previewDraft) { draft in
            PhotoEditDetailSheet(
                draft: bindingFor(draft.id),
                totalCount: photos.count,
                position: (photos.firstIndex(where: { $0.id == draft.id }) ?? 0) + 1,
                onDelete: { deletePhoto(id: draft.id) }
            )
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

    private func bindingFor(_ id: UUID) -> Binding<PhotoDraft> {
        Binding(
            get: { photos.first(where: { $0.id == id }) ?? PhotoDraft(imageData: Data(), priority: 0) },
            set: { newDraft in
                if let index = photos.firstIndex(where: { $0.id == id }) {
                    photos[index] = newDraft
                }
            }
        )
    }

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
    @Binding var photo: PhotoDraft

    var body: some View {
        HStack(spacing: 12) {
            if let image = photo.imageData.asImage() {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.small))
            }
            Text(photo.caption.isEmpty ? "No caption" : photo.caption)
                .foregroundStyle(photo.caption.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
        }
    }
}

// MARK: - Photo Edit Detail Sheet

private struct PhotoEditDetailSheet: View {
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
        PhotoPickerView(photos: .constant([]))
    }
}
