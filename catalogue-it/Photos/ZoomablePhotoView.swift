//
//  ZoomablePhotoView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 30/03/2026.
//

import SwiftUI

// MARK: - Zoomable Photo View

/// A single photo page with pinch-to-zoom, pan, and double-tap-to-toggle-zoom.
/// Each instance owns its own zoom/pan state so photos in a pager don't share state.
///
/// Gesture architecture:
/// - Pinch (MagnifyGesture) sits on the ZStack via `.simultaneousGesture` so it always fires,
///   even when the pan overlay is present. Previously it was on the image below the overlay;
///   the overlay's `contentShape` swallowed all touches and blocked it (bug 2).
/// - Pan (DragGesture) lives on a conditional overlay that only exists when zoomed.
///   At 1×, no DragGesture is in the tree → the parent ScrollView handles all drags for paging.
///   When zoomed, the parent disables its ScrollView via `.scrollDisabled`, so the pan overlay
///   is the sole drag responder.
/// - Both gestures track start state in @State (never @GestureState). @GestureState resets to
///   its initial value *before* onEnded fires, causing a one-frame snap-back (bug 4).
struct ZoomablePhotoView: View {
    let imageData: Data
    @Binding var isZoomed: Bool
    @Binding var isPinching: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var loadedImage: Image?
    // Natural size of the decoded image, used for accurate pan clamping.
    @State private var imageNaturalSize: CGSize = .zero

    // Committed transform — stable between gestures
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero

    // Pinch gesture start state (@State, never @GestureState)
    @State private var pinchStartZoom: CGFloat = 1.0
    @State private var pinchStartPan: CGSize = .zero
    @State private var pinchFocal: CGPoint = .zero

    // Drag gesture start state (@State, never @GestureState)
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
                                // Pan overlay: captures all touches when zoomed so the parent
                                // ScrollView's horizontal paging cannot fire.
                                // Double-tap must be mirrored here because the overlay's
                                // contentShape intercepts all taps before they reach the image.
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
            // Pinch at ZStack level so it fires regardless of whether the overlay is present.
            .simultaneousGesture(pinchGesture(in: geometry.size))
            .contentShape(Rectangle())
            .onChange(of: currentlyZoomed) { _, zoomed in
                isZoomed = zoomed
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

    /// Pinch-to-zoom with focal-point anchoring. Placed on the ZStack so it always fires.
    ///
    /// Focal-point math: the image point under the pinch centre must stay under it after
    /// rescaling. Solving the inverse transform gives:
    ///   newPan = d × (1 − ratio) + startPan × ratio
    /// where d = focalPoint − viewCentre and ratio = newZoom / startZoom.
    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Capture start state on the first frame of each new gesture.
                // isPinching doubles as the "gesture active" flag to avoid re-capturing.
                if !isPinching {
                    isPinching = true
                    pinchStartZoom = zoomScale
                    pinchStartPan = panOffset
                    pinchFocal = value.startLocation
                }

                // value.magnification is cumulative from gesture start (1.0 = no change).
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

    /// Pan gesture on the zoom overlay. Uses @State tracking to avoid @GestureState snap-back:
    /// @GestureState resets to .zero before onEnded fires, causing a visible one-frame jump.
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
            // Zoom to 2× anchored at the tap point, clamped so the image stays on-screen.
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

    /// The dimensions the image occupies when rendered by `.scaledToFit` in the given view.
    private func fittedImageSize(in viewSize: CGSize) -> CGSize {
        guard imageNaturalSize.width > 0, imageNaturalSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            // Fall back to full view size (worst-case: allows panning to the view edge)
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

    /// Clamp pan so no image edge passes the corresponding view edge.
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
