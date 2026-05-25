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
            PhotoGridView(
                photos: $photos,
                isEditing: isEditingPhotos,
                onTap: { id in
                    guard let draft = photos.first(where: { $0.id == id }) else { return }
                    previewDraft = draft
                },
                onDelete: { id in pendingDeleteId = id },
                onMove: movePhoto
            )

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
            Button("Delete Photo", role: .destructive) {
                if let id = pendingDeleteId { deletePhoto(id: id) }
            }
        }
        .sheet(item: $previewDraft) { draft in
            PhotoEditDetailSheet(
                draft: bindingFor(draft.id),
                totalCount: photos.count,
                position: (photos.firstIndex(where: { $0.id == draft.id }) ?? 0) + 1,
                onDelete: { pendingDeleteId = draft.id }
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
    let isEditing: Bool
    let onTap: (UUID) -> Void
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
                    PhotoThumbnailView(
                        photo: $photo,
                        isEditing: isEditing,
                        onTap: { onTap(photo.id) },
                        onDelete: { onDelete(photo.id) }
                    )
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
            .onChange(of: isEditing) { _, editing in
                if !editing { draggingId = nil }
            }
        }
    }

    @ViewBuilder
    private var liftedPhotoOverlay: some View {
        if let id = draggingId,
           let snapshot = photos.first(where: { $0.id == id }) {
            let safeBinding = Binding<PhotoDraft>(
                get: { photos.first(where: { $0.id == id }) ?? snapshot },
                set: { _ in }
            )
            PhotoThumbnailView(photo: safeBinding, isEditing: true, onTap: {}, onDelete: {})
                .matchedGeometryEffect(id: id, in: gridNamespace, isSource: true)
                .scaleEffect(1.06)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .position(dragPosition)
                .allowsHitTesting(false)
        }
    }

    private func reorderGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("photoGrid"))
            .onChanged { drag in
                guard isEditing else { return }
                if draggingId == nil {
                    if let frame = cellFrames[id] {
                        dragPosition = CGPoint(x: frame.midX, y: frame.midY)
                    }
                    withAnimation(.spring(duration: 0.2)) { draggingId = id }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                }
                dragPosition = drag.location
                swapIfNeeded(id: id)
            }
            .onEnded { _ in
                guard isEditing else { return }
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
    let isEditing: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                    .onTapGesture {
                        if !isEditing { onTap() }
                    }
            }

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 22))
                }
                .accessibilityLabel("Delete Photo")
                .padding(4)
                .transition(.scale.combined(with: .opacity))
            }
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
