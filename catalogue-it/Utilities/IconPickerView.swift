//
//  IconPickerView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Icon Picker View

/// Grid of curated SF Symbols.
///
/// Comes in two flavours: `init(selectedIcon:)` for a required icon (a catalogue always has
/// one), and `init(optionalIcon:)` for a field flag, where "no icon" is a real choice and
/// gets its own cell ahead of the categories.
struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var selectedIcon: String?
    private let allowsNoIcon: Bool

    /// Picker for a value that must always be some icon.
    init(selectedIcon: Binding<String>) {
        self._selectedIcon = Binding(
            get: { selectedIcon.wrappedValue },
            set: { if let newValue = $0 { selectedIcon.wrappedValue = newValue } }
        )
        self.allowsNoIcon = false
    }

    /// Picker for a value where `nil` — no icon at all — is a valid selection.
    init(optionalIcon: Binding<String?>) {
        self._selectedIcon = optionalIcon
        self.allowsNoIcon = true
    }

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
        ("Status", ["checkmark.circle.fill", "exclamationmark.triangle.fill", "wrench.fill", "shippingbox.fill", "eye.fill"]),
        ("Other", ["hammer.fill", "paintbrush.fill", "scissors", "keyboard.fill", "questionmark.circle.fill"])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if allowsNoIcon {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("None")
                                .font(.headline)
                                .padding(.horizontal)

                            Button {
                                selectedIcon = nil
                                dismiss()
                            } label: {
                                cell(systemImage: "slash.circle", isSelected: selectedIcon == nil)
                            }
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("No Icon")
                            .padding(.horizontal)
                        }
                    }

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
                                        cell(systemImage: icon, isSelected: selectedIcon == icon)
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

    private func cell(systemImage: String, isSelected: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .frame(width: 60, height: 60)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
    }
}

#Preview("Icon Picker") {
    IconPickerView(selectedIcon: .constant("star.fill"))
}

#Preview("Optional Icon Picker") {
    IconPickerView(optionalIcon: .constant(nil))
}
