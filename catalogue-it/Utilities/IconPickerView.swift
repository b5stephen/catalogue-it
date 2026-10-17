//
//  IconPickerView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI

// MARK: - Icon Picker View

/// `init(optionalIcon:)` is for flags, where no icon is a real choice. Only catalogues offer
/// emoji: a flag icon is small, tinted and beside text, where an emoji reads as clutter.
struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var selectedIcon: String?
    private let allowsNoIcon: Bool
    private let allowsEmoji: Bool
    @State private var mode: IconMode
    @State private var customEmoji: String = ""

    private enum IconMode: Hashable {
        case symbol
        case emoji
    }

    init(selectedIcon: Binding<String>) {
        self._selectedIcon = Binding(
            get: { selectedIcon.wrappedValue },
            set: { if let newValue = $0 { selectedIcon.wrappedValue = newValue } }
        )
        self.allowsNoIcon = false
        self.allowsEmoji = true
        // Open on the tab the current icon came from.
        let isEmoji = CatalogueIcon(storedValue: selectedIcon.wrappedValue).isEmoji
        self._mode = State(initialValue: isEmoji ? .emoji : .symbol)
    }

    init(optionalIcon: Binding<String?>) {
        self._selectedIcon = optionalIcon
        self.allowsNoIcon = true
        self.allowsEmoji = false
        self._mode = State(initialValue: .symbol)
    }

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

    // Parallel to the symbol categories, so switching tabs feels like the same shelf.
    let emojiCategories: [(String, [String])] = [
        ("Collections", ["🗂️", "📦", "🧰", "🗃️"]),
        ("Objects", ["⭐️", "❤️", "🔖", "🚩", "🏷️"]),
        ("Items", ["📷", "📚", "📰", "📖", "📄"]),
        ("Sports", ["⚽️", "🏀", "🏈", "⚾️", "🎾"]),
        ("Entertainment", ["📺", "🎵", "🎬", "🎮", "🎸"]),
        ("Nature", ["🍃", "🌳", "🌍", "☁️", "🌙"]),
        ("Transportation", ["🚗", "✈️", "🚂", "⛵️", "🚲"]),
        ("Food", ["☕️", "🍴", "🍷", "🎂", "🥡"]),
        ("Shopping", ["👜", "🛒", "💳", "🎁", "🧺"]),
        ("Hobbies", ["🧩", "🪁", "🎲", "🧵", "🪆"]),
        ("Other", ["🔨", "🎨", "✂️", "⌨️", "❓"])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                // Not lazy: the tabs' categories share names, so a LazyVStack reuses their rows when the
                // sections swap and the switch appears to do nothing. `id(mode)` forces a fresh identity.
                VStack(alignment: .leading, spacing: 20) {
                    if allowsEmoji {
                        Picker("Icon Style", selection: $mode) {
                            Text("Symbols").tag(IconMode.symbol)
                            Text("Emoji").tag(IconMode.emoji)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    Group {
                        if mode == .emoji {
                            emojiSection
                        } else {
                            symbolSection
                        }
                    }
                    .id(mode)
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

    // MARK: - Symbols

    @ViewBuilder
    private var symbolSection: some View {
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

    // MARK: - Emoji

    @ViewBuilder
    private var emojiSection: some View {
        // The escape hatch for a collection no shortlist would guess.
        VStack(alignment: .leading, spacing: 12) {
            Text("Any Emoji")
                .font(.headline)
                .padding(.horizontal)

            TextField("Type or paste an emoji", text: $customEmoji)
                .textFieldStyle(.roundedBorder)
                .onChange(of: customEmoji) { _, newValue in
                    // On change, not submit: the emoji keyboard has no return key.
                    guard let emoji = newValue.first(where: { $0.isEmoji }) else { return }
                    selectedIcon = String(emoji)
                    dismiss()
                }
                .padding(.horizontal)
        }

        ForEach(emojiCategories, id: \.0) { category, emoji in
            VStack(alignment: .leading, spacing: 12) {
                Text(category)
                    .font(.headline)
                    .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                    ForEach(emoji, id: \.self) { item in
                        Button {
                            selectedIcon = item
                            dismiss()
                        } label: {
                            cell(isSelected: selectedIcon == item) {
                                Text(item).font(.largeTitle)
                            }
                        }
                        .accessibilityLabel(item)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Cell

    private func cell(systemImage: String, isSelected: Bool) -> some View {
        cell(isSelected: isSelected) {
            Image(systemName: systemImage).font(.title2)
        }
    }

    private func cell(isSelected: Bool, @ViewBuilder content: () -> some View) -> some View {
        content()
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
