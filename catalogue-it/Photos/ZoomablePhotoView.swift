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
/// - Zoom uses `.simultaneousGesture` so it never blocks the parent ScrollView pager.
/// - Pan is attached via a conditional overlay that only exists when zoomed.
///   At 1×, no DragGesture is in the tree → the parent ScrollView handles all drags.
///   When zoomed, the parent disables its ScrollView via `.scrollDisabled(isZoomed)`,
///   so the pan overlay is the only gesture responder.
struct ZoomablePhotoView: View {
    let imageData: Data
    let caption: String?
    @Binding var isZoomed: Bool
    @Binding var isPinching: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero

    // Use @State (not @GestureState) for magnification to avoid the snap-back jump
    // that happens when @GestureState resets to 1.0 before onEnded fires.
    @State private var gestureMagnification: CGFloat = 1.0
    @GestureState private var gesturePan: CGSize = .zero

    private var currentZoom: CGFloat { zoomScale * gestureMagnification }
    private var currentlyZoomed: Bool { currentZoom > 1.01 }

    private var springAnimation: Animation {
        reduceMotion ? .linear(duration: 0.1) : .spring(duration: 0.35, bounce: 0.15)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if let image = imageData.asImage() {
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(currentZoom)
                        .offset(
                            x: panOffset.width + gesturePan.width,
                            y: panOffset.height + gesturePan.height
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .simultaneousGesture(zoomGesture)
                        .onTapGesture(count: 2) { location in
                            handleDoubleTap(at: location, in: geometry.size)
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Photo, double-tap to zoom")
                        .overlay {
                            if currentlyZoomed {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture()
                                            .updating($gesturePan) { value, state, _ in
                                                state = value.translation
                                            }
                                            .onEnded { value in
                                                let newOffset = CGSize(
                                                    width: panOffset.width + value.translation.width,
                                                    height: panOffset.height + value.translation.height
                                                )
                                                withAnimation(springAnimation) {
                                                    panOffset = clampedOffset(newOffset, zoom: zoomScale)
                                                }
                                            }
                                    )
                                    // The overlay intercepts all touches when zoomed, so the
                                    // double-tap on the image below never fires. Mirror it here.
                                    .onTapGesture(count: 2) { location in
                                        handleDoubleTap(at: location, in: geometry.size)
                                    }
                            }
                        }
                        .onChange(of: currentlyZoomed) { _, zoomed in
                            isZoomed = zoomed
                        }
                } else {
                    Rectangle()
                        .fill(.secondary.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }

                if let caption, !caption.isEmpty {
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

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                gestureMagnification = value.magnification
                isPinching = true
            }
            .onEnded { value in
                let newScale = min(max(zoomScale * value.magnification, 1.0), 5.0)
                // Set both in the same animation transaction to avoid jump
                withAnimation(springAnimation) {
                    zoomScale = newScale
                    gestureMagnification = 1.0
                    if newScale <= 1.0 {
                        panOffset = .zero
                    }
                }
                isPinching = false
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
            let anchorOffset = CGSize(
                width: (size.width / 2 - location.x),
                height: (size.height / 2 - location.y)
            )
            withAnimation(springAnimation) {
                zoomScale = 2.0
                panOffset = anchorOffset
            }
        }
    }

    /// Clamp pan offset so the image can't be dragged fully off-screen.
    private func clampedOffset(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let maxX = max(0, (zoom - 1) * 150)
        let maxY = max(0, (zoom - 1) * 200)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}
