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

    // Reflects whether the currently visible photo is zoomed in.
    // Set by ZoomablePhotoView via binding; gates paging and dismiss.
    @State private var isZoomed = false

    // Swipe-to-dismiss state
    @State private var dismissOffset: CGFloat = 0
    @State private var dismissProgress: CGFloat = 0 // 0 = fully presented, 1 = dismissed
#endif

    init(photos: [ItemPhoto], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        _selectedIndex = State(initialValue: initialIndex)
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
        ZStack {
            // Background fades during dismiss drag
            Color.black
                .opacity(1.0 - dismissProgress * 0.5)
                .ignoresSafeArea()

            // Photo pager — moves and scales during dismiss drag
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(photos.enumerated(), id: \.element.id) { index, photo in
                            ZoomablePhotoView(
                                imageData: photo.imageData,
                                caption: photo.caption,
                                isZoomed: $isZoomed
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
                .scrollDisabled(isZoomed)
            }
            .offset(y: dismissOffset)
            .scaleEffect(1.0 - dismissProgress * 0.1)
            // simultaneousGesture lets the ScrollView's horizontal paging and
            // this vertical dismiss gesture both recognise touches concurrently.
            .simultaneousGesture(dismissGesture)

            // Page indicator dots
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
        }
        .overlay(alignment: .top) {
            toolbarOverlay
        }
        .statusBarHidden(true)
        .onChange(of: selectedIndex) {
            let animation: Animation = reduceMotion ? .linear(duration: 0.1) : .spring
            withAnimation(animation) {
                isZoomed = false
            }
        }
    }

    // MARK: - Dismiss Gesture

    // Vertical downward drag to dismiss. Uses simultaneousGesture on the parent
    // so horizontal ScrollView paging is unaffected. A directionality check
    // (height > width * 1.5) prevents accidental activation on diagonal swipes.
    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isZoomed, value.translation.height > 0 else { return }
                let dominated = abs(value.translation.height) > abs(value.translation.width) * 1.5
                guard dominated else { return }
                if !reduceMotion {
                    dismissOffset = value.translation.height
                    dismissProgress = min(dismissOffset / 300, 1.0)
                }
            }
            .onEnded { value in
                let didDragFar = value.translation.height > 100
                let didDragFast = value.velocity.height > 600
                if didDragFar || didDragFast {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(duration: 0.3)) {
                        dismissOffset = 0
                        dismissProgress = 0
                    }
                }
            }
    }

    // MARK: - Toolbar Overlay

    @ViewBuilder
    private var toolbarOverlay: some View {
        HStack {
            Button("Close", systemImage: "xmark") {
                dismiss()
            }
            .symbolVariant(.circle.fill)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.4))
            .font(.title2)
            .padding(.leading, 16)
            .padding(.top, 8)

            Spacer()

            if selectedIndex < photos.count {
                ShareLink(
                    item: PhotoTransferable(data: photos[selectedIndex].imageData),
                    preview: SharePreview(photos[selectedIndex].caption ?? "Photo")
                ) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.4))
                        .font(.title2)
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
        }
    }
#endif

    // MARK: - macOS Body

    private var macOSBody: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(photos.enumerated(), id: \.element.id) { index, photo in
                                macOSPhotoPage(photo: photo)
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
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func macOSPhotoPage(photo: ItemPhoto) -> some View {
        ZStack(alignment: .bottom) {
            if let image = photo.imageData.asImage() {
                image
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
