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

// MARK: - Cell Frame Preference

private struct CellFramePreference: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Photo Grid View

@MainActor
private struct PhotoGridView: View {
    @Binding var photos: [PhotoDraft]
    let onDelete: (UUID) -> Void
    let onMove: (UUID, UUID) -> Void

    @Namespace private var gridNamespace
    @State private var draggingId: UUID?
    @State private var dragPosition: CGPoint = .zero
    @State private var cellFrames: [UUID: CGRect] = [:]

    private let cellSize = AppConstants.ThumbnailSize.photoPicker
    private let spacing: CGFloat = 12

    var body: some View {
        if !photos.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cellSize), spacing: spacing)],
                spacing: spacing
            ) {
                ForEach($photos) { $photo in
                    let isLifted = draggingId == photo.id
                    PhotoThumbnailView(photo: $photo, onDelete: { onDelete(photo.id) })
                        .matchedGeometryEffect(id: photo.id, in: gridNamespace, isSource: !isLifted)
                        .opacity(isLifted ? 0 : 1)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: CellFramePreference.self,
                                    value: [photo.id: geo.frame(in: .named("photoGrid"))]
                                )
                            }
                        )
                        .gesture(reorderGesture(for: photo.id))
                }
            }
            .padding(.vertical, 4)
            .coordinateSpace(.named("photoGrid"))
            .overlay(alignment: .topLeading) { liftedPhotoOverlay }
            .onPreferenceChange(CellFramePreference.self) { cellFrames = $0 }
        }
    }

    @ViewBuilder
    private var liftedPhotoOverlay: some View {
        if let id = draggingId,
           let idx = photos.firstIndex(where: { $0.id == id }) {
            PhotoThumbnailView(photo: $photos[idx], onDelete: {})
                .matchedGeometryEffect(id: id, in: gridNamespace, isSource: true)
                .scaleEffect(1.06)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .position(dragPosition)
                .allowsHitTesting(false)
        }
    }

    private func reorderGesture(for id: UUID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("photoGrid")))
            .onChanged { value in
                switch value {
                case .first(true):
                    if let frame = cellFrames[id] {
                        dragPosition = CGPoint(x: frame.midX, y: frame.midY)
                    }
                    withAnimation(.spring(duration: 0.2)) { draggingId = id }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                case .second(true, let drag?):
                    dragPosition = drag.location
                    swapIfNeeded(id: id)
                default:
                    break
                }
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.1)) { draggingId = nil }
            }
    }

    private func swapIfNeeded(id: UUID) {
        guard let targetId = cellFrames.first(where: {
            $0.key != id && $0.value.contains(dragPosition)
        })?.key else { return }

        withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
            onMove(id, targetId)
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
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
