//
//  FullScreenPhotoView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Full Screen Photo View

struct FullScreenPhotoView: View {
    let photos: [ItemPhoto]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int

#if os(iOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Set by ZoomablePhotoView; gates paging and dismiss.
    @State private var isZoomed = false

    // Gates dismiss separately: isZoomed is still false while a pinch is leaving 1×.
    @State private var isPinching = false

    @State private var dismissOffset: CGFloat = 0
    @State private var dismissProgress: CGFloat = 0 // 0 = fully presented, 1 = dismissed

    // Latched when horizontal motion comes first, so a sideways swipe never dismisses.
    @State private var dismissSuppressed = false
#endif

    init(photos: [ItemPhoto], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        _selectedIndex = State(initialValue: initialIndex)
    }

    private var adaptiveBackground: Color {
#if os(iOS)
        Color(uiColor: .systemBackground)
#else
        Color(nsColor: .windowBackgroundColor)
#endif
    }

    var body: some View {
#if os(iOS)
        iOSBody
#else
        macOSBody
#endif
    }

#if os(iOS)
    // MARK: - iOS Body

    private var iOSBody: some View {
        NavigationStack {
            ZStack {
                adaptiveBackground
                    .opacity(1.0 - dismissProgress * 0.5)
                    .ignoresSafeArea()

                GeometryReader { proxy in
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal) {
                            HStack(spacing: 0) {
                                ForEach(photos.enumerated(), id: \.element.id) { index, photo in
                                    ZoomablePhotoView(
                                        imageData: photo.imageData,
                                        isZoomed: $isZoomed,
                                        isPinching: $isPinching
                                    )
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .id(index)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollIndicators(.hidden)
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: Binding(
                            get: { selectedIndex as Int? },
                            set: { if let i = $0 { selectedIndex = i } }
                        ))
                        .scrollDisabled(isZoomed || isPinching)
                        // scrollPosition(id:) doesn't reliably set initial position on
                        // first render; scrollTo with initial: true seeds it directly.
                        .onChange(of: initialIndex, initial: true) { _, index in
                            scrollProxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
                .offset(y: dismissOffset)
                .scaleEffect(1.0 - dismissProgress * 0.1)
                // Simultaneous, so horizontal paging keeps working.
                .simultaneousGesture(dismissGesture)

                if photos.count > 1 {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(0..<photos.count, id: \.self) { i in
                                Circle()
                                    .fill(.primary.opacity(selectedIndex == i ? 1 : 0.4))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
                if selectedIndex < photos.count {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(
                            item: PhotoTransferable(data: photos[selectedIndex].imageData),
                            preview: SharePreview(photos[selectedIndex].caption ?? "Photo")
                        )
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .statusBarHidden(true)
        .onChange(of: selectedIndex) {
            let animation: Animation = reduceMotion ? .linear(duration: 0.1) : .spring
            withAnimation(animation) {
                isZoomed = false
            }
            isPinching = false
            dismissSuppressed = false
        }
    }

    // MARK: - Dismiss Gesture

    // Within ~18° of vertical (3×), and 20pt in before any feedback, which avoids a
    // one-frame jump at the start.
    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isZoomed, !isPinching else { return }

                let height = value.translation.height
                let width = value.translation.width

                if abs(width) > abs(height) {
                    dismissSuppressed = true
                }
                guard !dismissSuppressed, height > 0 else { return }

                guard abs(height) > abs(width) * 3.0 else { return }

                guard height > 20 else { return }

                if !reduceMotion {
                    dismissOffset = height
                    dismissProgress = min(dismissOffset / 300, 1.0)
                }
            }
            .onEnded { value in
                defer { dismissSuppressed = false }

                let didDragFar = value.translation.height > 100
                let didDragFast = value.velocity.height > 600
                // A pinch can end here after isPinching resets; only a drag that onChanged
                // tracked (dismissOffset > 0) may dismiss.
                if !dismissSuppressed, dismissOffset > 0, (didDragFar || didDragFast) {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(duration: 0.3)) {
                        dismissOffset = 0
                        dismissProgress = 0
                    }
                }
            }
    }

#endif

    // MARK: - macOS Body

#if os(macOS)
    private var macOSBody: some View {
        NavigationStack {
            ZStack {
                adaptiveBackground.ignoresSafeArea()

                GeometryReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(photos.enumerated(), id: \.element.id) { index, photo in
                                MacOSPhotoPage(photo: photo)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: Binding(
                        get: { selectedIndex as Int? },
                        set: { if let i = $0 { selectedIndex = i } }
                    ))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }

                if selectedIndex < photos.count {
                    ToolbarItem(placement: .confirmationAction) {
                        ShareLink(
                            item: PhotoTransferable(data: photos[selectedIndex].imageData),
                            preview: SharePreview(photos[selectedIndex].caption ?? "Photo")
                        )
                    }
                }

                ToolbarItemGroup(placement: .navigation) {
                    Button("Previous", systemImage: "chevron.left") {
                        selectedIndex -= 1
                    }
                    .disabled(selectedIndex == 0)

                    Text("\(selectedIndex + 1) of \(photos.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Button("Next", systemImage: "chevron.right") {
                        selectedIndex += 1
                    }
                    .disabled(selectedIndex >= photos.count - 1)
                }
            }
        }
    }
#endif

}

// MARK: - macOS Photo Page

#if os(macOS)
private struct MacOSPhotoPage: View {
    let photo: ItemPhoto
    @State private var loadedImage: Image?

    var body: some View {
        Group {
            if let loadedImage {
                loadedImage
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .task(id: photo.persistentModelID) {
            let data = photo.imageData
            loadedImage = await Task.detached(priority: .userInitiated) {
                NSImage(data: data).map { Image(nsImage: $0) }
            }.value
        }
    }
}
#endif

// MARK: - Photo Transferable

private struct PhotoTransferable: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.data }
    }
}
