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

    init(photos: [ItemPhoto], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $selectedIndex) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        photoPage(photo: photo)
                            .tag(index)
                    }
                }
#if os(iOS)
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
#endif
            }
#if os(iOS)
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
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func photoPage(photo: ItemPhoto) -> some View {
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
