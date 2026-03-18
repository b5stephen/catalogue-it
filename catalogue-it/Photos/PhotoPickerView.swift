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

    var body: some View {
        let loading = isLoadingPhotos
        Section("Photos") {
            PhotoScrollView(photos: $photos, onDelete: deletePhoto)

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
        }
        .alert("Couldn't Load Photo", isPresented: Binding<Bool>(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError?.localizedDescription ?? "")
        }
    }

    private func loadPhotos() {
        guard !selectedItems.isEmpty else { return }
        isLoadingPhotos = true

        Task {
            var newDrafts: [PhotoDraft] = []
            let startOrder = photos.count

            for (index, item) in selectedItems.enumerated() {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let compressed = data.compressedAsJPEG(quality: 0.8) else { continue }
                    newDrafts.append(PhotoDraft(imageData: compressed, sortOrder: startOrder + index))
                } catch {
                    loadError = error
                }
            }

            photos.append(contentsOf: newDrafts)
            selectedItems = []
            isLoadingPhotos = false
        }
    }

    private func deletePhoto(id: UUID) {
        photos.removeAll { $0.id == id }
        for index in photos.indices {
            photos[index].sortOrder = index
        }
    }
}

// MARK: - Photo Scroll View

private struct PhotoScrollView: View {
    @Binding var photos: [PhotoDraft]
    let onDelete: (UUID) -> Void

    var body: some View {
        if !photos.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach($photos) { $photo in
                        PhotoThumbnailView(photo: $photo) {
                            onDelete(photo.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Photo Thumbnail View

private struct PhotoThumbnailView: View {
    @Binding var photo: PhotoDraft
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let image = photo.imageData.asImage() {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: AppConstants.ThumbnailSize.photoPicker,
                               height: AppConstants.ThumbnailSize.photoPicker)
                        .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.small))
                }

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 18))
                }
                .accessibilityLabel("Delete Photo")
                .padding(4)
            }

            TextField("Caption", text: $photo.caption)
                .font(.caption)
                .frame(width: AppConstants.ThumbnailSize.photoPicker)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Preview

#Preview {
    Form {
        PhotoPickerView(photos: .constant([]))
    }
}
