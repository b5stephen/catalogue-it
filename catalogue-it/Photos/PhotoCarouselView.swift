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
    @State private var showingFullScreen = false

    var body: some View {
        ZStack(alignment: .bottom) {
#if os(iOS)
            TabView(selection: $selectedIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    photoPage(photo: photo)
                        .tag(index)
                        .onTapGesture {
                            showingFullScreen = true
                        }
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

            if (selectedIndex ?? 0) < photos.count,
               let caption = photos[selectedIndex ?? 0].caption,
               !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 28)
            }
        }
#if os(iOS)
        .fullScreenCover(isPresented: $showingFullScreen) {
            FullScreenPhotoView(photos: photos, initialIndex: selectedIndex ?? 0)
        }
#else
        .sheet(isPresented: $showingFullScreen) {
            FullScreenPhotoView(photos: photos, initialIndex: selectedIndex ?? 0)
        }
#endif
    }

    @ViewBuilder
    private func photoPage(photo: ItemPhoto) -> some View {
        if let image = photo.imageData.asImage() {
            image
                .resizable()
                .scaledToFill()
                .clipped()
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
}
