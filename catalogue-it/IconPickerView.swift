//
//  IconPickerView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Icon Picker View

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String

    // Curated list of good catalogue icons
    let iconCategories: [(String, [String])] = [
        ("Collections", ["square.grid.2x2", "square.grid.3x3", "rectangle.grid.3x2", "circle.grid.3x3"]),
        ("Objects", ["star.fill", "heart.fill", "bookmark.fill", "flag.fill", "tag.fill"]),
        ("Items", ["photo.fill", "book.fill", "magazine.fill", "newspaper.fill", "doc.fill"]),
        ("Sports", ["sportscourt.fill", "baseball.fill", "football.fill", "basketball.fill", "tennisball.fill"]),
        ("Entertainment", ["tv.fill", "music.note", "film.fill", "gamecontroller.fill", "guitars.fill"]),
        ("Nature", ["leaf.fill", "tree.fill", "globe.americas.fill", "cloud.fill", "moon.fill"]),
        ("Transportation", ["car.fill", "airplane", "train.side.front.car", "sailboat.fill", "bicycle"]),
        ("Food", ["cup.and.saucer.fill", "fork.knife", "wineglass.fill", "birthday.cake.fill", "takeoutbag.and.cup.and.straw.fill"]),
        ("Shopping", ["bag.fill", "cart.fill", "creditcard.fill", "giftcard.fill", "basket.fill"]),
        ("Other", ["hammer.fill", "wrench.fill", "paintbrush.fill", "scissors", "keyboard.fill"])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(iconCategories, id: \.0) { category, icons in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category)
                                .font(.headline)
                                .padding(.horizontal)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                                ForEach(icons, id: \.self) { icon in
                                    Button {
                                        selectedIcon = icon
                                        dismiss()
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.title2)
                                            .frame(width: 60, height: 60)
                                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                            .clipShape(.rect(cornerRadius: 12))
                                            .overlay {
                                                if selectedIcon == icon {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.accentColor, lineWidth: 2)
                                                }
                                            }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Choose Icon")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview("Icon Picker") {
    IconPickerView(selectedIcon: .constant("star.fill"))
}
