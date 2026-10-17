//
//  ZoomablePhotoView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 30/03/2026.
//

import SwiftUI

// MARK: - Zoomable Photo View

/// - Pinch sits on the ZStack so the pan overlay's `contentShape` can't swallow it.
/// - Pan exists only while zoomed, so at 1× the parent pager gets every drag; zoomed, the
///   parent disables its scrolling.
/// - Start state lives in @State, never @GestureState, which resets *before* onEnded and
///   snaps back for a frame.
struct ZoomablePhotoView: View {
    let imageData: Data
    @Binding var isZoomed: Bool
    @Binding var isPinching: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var loadedImage: Image?
    @State private var imageNaturalSize: CGSize = .zero

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero

    @State private var pinchStartZoom: CGFloat = 1.0
    @State private var pinchStartPan: CGSize = .zero
    @State private var pinchFocal: CGPoint = .zero

    @State private var dragActive = false
    @State private var dragStartPan: CGSize = .zero

    private var currentlyZoomed: Bool { zoomScale > 1.01 }

    private var springAnimation: Animation {
        reduceMotion ? .linear(duration: 0.1) : .spring(duration: 0.35, bounce: 0.15)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let loadedImage {
                    loadedImage
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoomScale)
                        .offset(x: panOffset.width, y: panOffset.height)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay {
                            if currentlyZoomed {
                                // Double-tap is repeated here: the overlay intercepts taps
                                // before they reach the image.
                                Color.clear
                                    .contentShape(Rectangle())
                                    .gesture(panGesture(in: geometry.size))
                                    .onTapGesture(count: 2) { location in
                                        handleDoubleTap(at: location, in: geometry.size)
                                    }
                            }
                        }
                        .onTapGesture(count: 2) { location in
                            handleDoubleTap(at: location, in: geometry.size)
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Photo, double-tap to zoom")
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
            .simultaneousGesture(pinchGesture(in: geometry.size))
            .contentShape(Rectangle())
            .onChange(of: currentlyZoomed) { _, zoomed in
                isZoomed = zoomed
            }
            // Gestures are the only other clamp, so a resize while zoomed would otherwise
            // leave an image edge past the view's edge.
            .onChange(of: geometry.size) { _, newSize in
                panOffset = clampedOffset(panOffset, zoom: zoomScale, in: newSize)
            }
        }
        .task(id: imageData) {
            let data = imageData
#if os(iOS)
            let result = await Task.detached(priority: .userInitiated) {
                UIImage(data: data).map { img in (Image(uiImage: img), img.size) }
            }.value
#else
            let result = await Task.detached(priority: .userInitiated) {
                NSImage(data: data).map { img in (Image(nsImage: img), img.size) }
            }.value
#endif
            if let (img, size) = result {
                loadedImage = img
                imageNaturalSize = size
            }
        }
    }

    // MARK: - Gestures

    /// Keeps the image point under the pinch centre in place:
    ///   newPan = d × (1 − ratio) + startPan × ratio
    /// where d = focalPoint − viewCentre and ratio = newZoom / startZoom.
    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // isPinching doubles as "start state captured".
                if !isPinching {
                    isPinching = true
                    pinchStartZoom = zoomScale
                    pinchStartPan = panOffset
                    pinchFocal = value.startLocation
                }

                let m = value.magnification
                let newZoom = max(1.0, min(5.0, pinchStartZoom * m))
                let ratio = newZoom / pinchStartZoom

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let d = CGSize(
                    width: pinchFocal.x - center.x,
                    height: pinchFocal.y - center.y
                )
                let newPan = CGSize(
                    width: d.width * (1 - ratio) + pinchStartPan.width * ratio,
                    height: d.height * (1 - ratio) + pinchStartPan.height * ratio
                )
                zoomScale = newZoom
                panOffset = clampedOffset(newPan, zoom: newZoom, in: size)
            }
            .onEnded { value in
                isPinching = false
                let newZoom = max(1.0, min(5.0, pinchStartZoom * value.magnification))
                withAnimation(springAnimation) {
                    if newZoom <= 1.0 {
                        zoomScale = 1.0
                        panOffset = .zero
                    } else {
                        zoomScale = newZoom
                        panOffset = clampedOffset(panOffset, zoom: newZoom, in: size)
                    }
                }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !dragActive {
                    dragActive = true
                    dragStartPan = panOffset
                }
                let newPan = CGSize(
                    width: dragStartPan.width + value.translation.width,
                    height: dragStartPan.height + value.translation.height
                )
                panOffset = clampedOffset(newPan, zoom: zoomScale, in: size)
            }
            .onEnded { value in
                dragActive = false
                let finalPan = CGSize(
                    width: dragStartPan.width + value.translation.width,
                    height: dragStartPan.height + value.translation.height
                )
                withAnimation(springAnimation) {
                    panOffset = clampedOffset(finalPan, zoom: zoomScale, in: size)
                }
            }
    }

    // MARK: - Actions

    private func handleDoubleTap(at location: CGPoint, in size: CGSize) {
        if zoomScale > 1.01 {
            withAnimation(springAnimation) {
                zoomScale = 1.0
                panOffset = .zero
            }
        } else {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let unclamped = CGSize(
                width: center.x - location.x,
                height: center.y - location.y
            )
            withAnimation(springAnimation) {
                zoomScale = 2.0
                panOffset = clampedOffset(unclamped, zoom: 2.0, in: size)
            }
        }
    }

    // MARK: - Helpers

    private func fittedImageSize(in viewSize: CGSize) -> CGSize {
        guard imageNaturalSize.width > 0, imageNaturalSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return viewSize
        }
        let scale = min(
            viewSize.width / imageNaturalSize.width,
            viewSize.height / imageNaturalSize.height
        )
        return CGSize(
            width: imageNaturalSize.width * scale,
            height: imageNaturalSize.height * scale
        )
    }

    private func clampedOffset(_ offset: CGSize, zoom: CGFloat, in viewSize: CGSize) -> CGSize {
        let fitted = fittedImageSize(in: viewSize)
        let maxX = max(0, (fitted.width * zoom - viewSize.width) / 2)
        let maxY = max(0, (fitted.height * zoom - viewSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}
