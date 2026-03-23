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
    #if os(iOS)
    @State private var isCameraPresented = false
    @State private var cameraCoordinator: CameraCoordinator?
    #endif

    var body: some View {
        let loading = isLoadingPhotos
        Section("Photos") {
            PhotoGridView(photos: $photos, onDelete: deletePhoto, onMove: movePhoto)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label(
                    loading ? "Loading…" : "Select Photos",
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
        photos.removeAll { $0.id == id }
        for index in photos.indices {
            photos[index].priority = index
        }
    }

    private func movePhoto(fromId: UUID, toId: UUID) {
        guard fromId != toId,
              let from = photos.firstIndex(where: { $0.id == fromId }),
              let to = photos.firstIndex(where: { $0.id == toId }) else { return }
        photos.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        for index in photos.indices {
            photos[index].priority = index
        }
    }
}

// MARK: - Photo Grid View

@MainActor
private struct PhotoGridView: View {
    @Binding var photos: [PhotoDraft]
    let onDelete: (UUID) -> Void
    let onMove: (UUID, UUID) -> Void

    @State private var draggingId: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var numColumns: Int = 3

    private let cellSize = AppConstants.ThumbnailSize.photoPicker
    private let spacing: CGFloat = 12
    private var stride: CGFloat { cellSize + spacing }

    var body: some View {
        if !photos.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cellSize), spacing: spacing)],
                spacing: spacing
            ) {
                ForEach($photos) { $photo in
                    let isLifted = draggingId == photo.id
                    PhotoThumbnailView(photo: $photo, onDelete: { onDelete(photo.id) })
                        .offset(isLifted ? dragOffset : .zero)
                        .scaleEffect(isLifted ? 1.06 : 1.0)
                        .shadow(color: isLifted ? .black.opacity(0.25) : .clear, radius: 8, y: 4)
                        .zIndex(isLifted ? 1 : 0)
                        .animation(.spring(duration: 0.2), value: isLifted)
                        .gesture(reorderGesture(for: photo.id))
                }
            }
            .padding(.vertical, 4)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { numColumns = columnCount(for: geo.size.width) }
                        .onChange(of: geo.size.width) { _, w in numColumns = columnCount(for: w) }
                }
            )
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (cellSize + spacing)))
    }

    private func reorderGesture(for id: UUID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    withAnimation(.spring(duration: 0.2)) { draggingId = id }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                case .second(true, let drag?):
                    dragOffset = drag.translation
                    swapIfNeeded(id: id)
                default:
                    break
                }
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.2)) {
                    draggingId = nil
                    dragOffset = .zero
                }
            }
    }

    private func swapIfNeeded(id: UUID) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }

        if dragOffset.width > stride / 2, idx < photos.count - 1 {
            onMove(id, photos[idx + 1].id)
            dragOffset.width -= stride
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } else if dragOffset.width < -stride / 2, idx > 0 {
            onMove(id, photos[idx - 1].id)
            dragOffset.width += stride
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } else if dragOffset.height > stride / 2, idx + numColumns < photos.count {
            onMove(id, photos[idx + numColumns].id)
            dragOffset.height -= stride
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } else if dragOffset.height < -stride / 2, idx >= numColumns {
            onMove(id, photos[idx - numColumns].id)
            dragOffset.height += stride
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
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
