//
//  FullScreenPhotoView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Full Screen Photo View

struct FullScreenPhotoView: View {
    let photos: [ItemPhoto]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int

#if os(iOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Zoom
    @GestureState private var gestureZoom: CGFloat = 1.0
    @State private var zoomScale: CGFloat = 1.0

    // Pan — only active via a conditional overlay when isZoomed, so it never
    // competes with the horizontal scroll pager when viewing at 1×.
    @GestureState private var gesturePan: CGSize = .zero
    @State private var panOffset: CGSize = .zero

    // Swipe-to-dismiss
    @State private var dismissOffset: CGFloat = 0

    private var currentZoom: CGFloat { zoomScale * gestureZoom }
    private var isZoomed: Bool { currentZoom > 1.01 }
#endif

    init(photos: [ItemPhoto], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                                photoPage(photo: photo)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: Binding<Int?>(
                        get: { selectedIndex },
                        set: { if let i = $0 { selectedIndex = i } }
                    ))
#if os(iOS)
                    .scrollDisabled(isZoomed)
#endif
                }

#if os(iOS)
                if photos.count > 1 {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(0..<photos.count, id: \.self) { i in
                                Circle()
                                    .fill(.white.opacity(selectedIndex == i ? 1 : 0.4))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
#endif
            }
#if os(iOS)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard !isZoomed, value.translation.height > 0 else { return }
                        if !reduceMotion {
                            dismissOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        let didDragFar = value.translation.height > 100
                        let didDragFast = value.velocity.height > 600
                        if didDragFar || didDragFast {
                            dismiss()
                        } else if !reduceMotion {
                            withAnimation(.spring(duration: 0.3)) { dismissOffset = 0 }
                        } else {
                            dismissOffset = 0
                        }
                    }
            )
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
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

#if os(macOS)
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        selectedIndex -= 1
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(selectedIndex == 0)

                    Text("\(selectedIndex + 1) of \(photos.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Button {
                        selectedIndex += 1
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(selectedIndex >= photos.count - 1)
                }
#endif
            }
        }
#if os(iOS)
        .offset(y: dismissOffset)
        .onChange(of: selectedIndex) {
            let animation: Animation = reduceMotion ? .linear(duration: 0.1) : .spring
            withAnimation(animation) {
                zoomScale = 1.0
                panOffset = .zero
                dismissOffset = 0
            }
        }
#endif
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func photoPage(photo: ItemPhoto) -> some View {
        ZStack(alignment: .bottom) {
            if let image = photo.imageData.asImage() {
#if os(iOS)
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(currentZoom)
                    .offset(
                        x: panOffset.width + gesturePan.width,
                        y: panOffset.height + gesturePan.height
                    )
                    .gesture(
                        MagnificationGesture()
                            .updating($gestureZoom) { value, state, _ in state = value }
                            .onEnded { value in
                                zoomScale = min(max(zoomScale * value, 1.0), 5.0)
                                if zoomScale <= 1.0 { panOffset = .zero }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.3)) {
                            zoomScale = 1.0
                            panOffset = .zero
                        }
                    }

                // Pan overlay exists only when zoomed. Its absence when at 1× means
                // there is no DragGesture inside the ScrollView to interfere with paging.
                if isZoomed {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .updating($gesturePan) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    panOffset.width += value.translation.width
                                    panOffset.height += value.translation.height
                                }
                        )
                }
#else
                image
                    .resizable()
                    .scaledToFit()
#endif
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }

            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Photo Transferable

/// Wraps image Data as a Transferable type for use with ShareLink.
private struct PhotoTransferable: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.data }
    }
}
