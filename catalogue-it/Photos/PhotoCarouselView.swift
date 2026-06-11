//
//  PhotoCarouselView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 15/03/2026.
//

import SwiftUI

// MARK: - Photo Carousel View

struct PhotoCarouselView: View {
    let photos: [ItemPhoto]

    @State private var selectedIndex: Int? = 0
#if os(iOS)
    @Namespace private var photoNamespace
    @State private var showingFullScreen = false
#else
    @State private var showingFullScreen = false
#endif

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
#if os(iOS)
                TabView(selection: $selectedIndex) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        photoPage(photo: photo)
                            .tag(index as Int?)
                            .onTapGesture {
                                showingFullScreen = true
                            }
                            .matchedTransitionSource(id: photo.id, in: photoNamespace)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
#else
                // macOS: custom pager since TabView(.page) is iOS-only
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            photoPage(photo: photo)
                                .containerRelativeFrame(.horizontal)
                                .tag(index)
                                .onTapGesture {
                                    showingFullScreen = true
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedIndex)
#endif
            }
            .frame(height: AppConstants.PhotoHeight.detail)

            let caption = (selectedIndex ?? 0) < photos.count ? photos[selectedIndex ?? 0].caption : nil
            Text(caption ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 24)
        }
#if os(iOS)
        .fullScreenCover(isPresented: $showingFullScreen) {
            FullScreenPhotoView(photos: photos, initialIndex: selectedIndex ?? 0)
                .navigationTransition(.zoom(
                    sourceID: photos[selectedIndex ?? 0].id,
                    in: photoNamespace
                ))
        }
#else
        .sheet(isPresented: $showingFullScreen) {
            FullScreenPhotoView(photos: photos, initialIndex: selectedIndex ?? 0)
        }
#endif
    }

    @ViewBuilder
    private func photoPage(photo: ItemPhoto) -> some View {
        Group {
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
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                copyImageToClipboard(photo.imageData)
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
        }
    }
}

private func copyImageToClipboard(_ data: Data) {
#if os(macOS)
    if let nsImage = NSImage(data: data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }
#else
    UIPasteboard.general.image = UIImage(data: data)
#endif
}
