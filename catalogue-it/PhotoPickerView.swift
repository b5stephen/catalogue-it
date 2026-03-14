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
struct PhotoPickerView: View {
    @Binding var photos: [PhotoDraft]

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos: Bool = false

    var body: some View {
        Section("Photos") {
            photoScrollView

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label(
                    isLoadingPhotos ? "Loading…" : "Add Photos",
                    systemImage: isLoadingPhotos ? "hourglass" : "photo.badge.plus"
                )
            }
            .disabled(isLoadingPhotos)
            .onChange(of: selectedItems) {
                loadPhotos()
            }
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var photoScrollView: some View {
        if !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach($photos) { $photo in
                        PhotoThumbnailView(photo: $photo) {
                            deletePhoto(id: photo.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func loadPhotos() {
        guard !selectedItems.isEmpty else { return }
        isLoadingPhotos = true

        Task {
            var newDrafts: [PhotoDraft] = []
            let startOrder = photos.count

            for (index, item) in selectedItems.enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let compressed = data.compressedAsJPEG(quality: 0.8)
                else { continue }
                newDrafts.append(PhotoDraft(imageData: compressed, sortOrder: startOrder + index))
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
                        .frame(width: 90, height: 90)
                        .clipShape(.rect(cornerRadius: 8))
                }

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 18))
                }
                .padding(4)
            }

            TextField("Caption", text: $photo.caption)
                .font(.caption)
                .frame(width: 90)
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
