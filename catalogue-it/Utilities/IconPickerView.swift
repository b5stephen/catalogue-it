//
//  IconPickerView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 14/03/2026.
//

import SwiftUI
import PhotosUI

// MARK: - Icon Picker View

/// `init(optionalIcon:)` is for flags, where no icon is a real choice. Only catalogues offer
/// emoji, Genmoji and photos: a flag icon is small, tinted and beside text, where they read as
/// clutter.
struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var selection: CatalogueIcon?
    private let allowsNoIcon: Bool
    private let allowsImages: Bool
    private let tint: Color
    @State private var mode: IconMode
    @State private var emojiKeyboardRequest = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var photoLoadFailed = false
#if os(iOS)
    @State private var cameraCoordinator: CameraCoordinator?
#endif

    private enum IconMode: Hashable {
        case symbol
        case emoji
        case photo
    }

    init(selectedIcon: Binding<CatalogueIcon>, tint: Color = .accentColor) {
        self._selection = Binding(
            get: { selectedIcon.wrappedValue },
            set: { if let newValue = $0 { selectedIcon.wrappedValue = newValue } }
        )
        self.allowsNoIcon = false
        self.allowsImages = true
        self.tint = tint
        // Open on the tab the current icon came from.
        let mode: IconMode = switch selectedIcon.wrappedValue {
        case .symbol: .symbol
        case .emoji, .genmoji: .emoji
        case .photo: .photo
        }
        self._mode = State(initialValue: mode)
    }

    init(optionalIcon: Binding<String?>) {
        self._selection = Binding(
            get: { optionalIcon.wrappedValue.map(CatalogueIcon.symbol) },
            set: { optionalIcon.wrappedValue = $0?.iconName }
        )
        self.allowsNoIcon = true
        self.allowsImages = false
        self.tint = .accentColor
        self._mode = State(initialValue: .symbol)
    }

    private func choose(_ icon: CatalogueIcon?) {
        selection = icon
        dismiss()
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
                    if allowsImages {
                        Picker("Icon Style", selection: $mode) {
                            Text("Symbols").tag(IconMode.symbol)
                            Text("Emoji").tag(IconMode.emoji)
                            Text("Photo").tag(IconMode.photo)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    Group {
                        switch mode {
                        case .symbol: symbolSection
                        case .emoji: emojiSection
                        case .photo: photoSection
                        }
                    }
                    .id(mode)
                }
                .padding(.vertical)
#if os(iOS)
                // With scrolling, the only ways out of the emoji keyboard on iPhone, which has no
                // dismiss key: the view it types into is hidden, so there's nothing to tap away from.
                .background {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                            )
                        }
                }
#endif
            }
            .scrollDismissesKeyboard(.immediately)
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
                    choose(nil)
                } label: {
                    cell(systemImage: "slash.circle", isSelected: selection == nil)
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
                            choose(.symbol(icon))
                        } label: {
                            cell(systemImage: icon, isSelected: selection == .symbol(icon))
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
        anyEmojiButton
            .padding(.horizontal)

        ForEach(emojiCategories, id: \.0) { category, emoji in
            VStack(alignment: .leading, spacing: 12) {
                Text(category)
                    .font(.headline)
                    .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                    ForEach(emoji, id: \.self) { item in
                        Button {
                            choose(.emoji(item))
                        } label: {
                            cell(isSelected: selection == .emoji(item)) {
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

    // The escape hatch for a collection no shortlist would guess, and the way in for Genmoji.
    private var anyEmojiButton: some View {
        Button { emojiKeyboardRequest += 1 } label: {
            ActionCard(
                systemImage: "face.smiling",
                title: "Any Emoji",
                subtitle: currentGenmoji == nil ? "Opens the emoji keyboard, including Genmoji" : nil,
                tint: tint
            ) {
                if let currentGenmoji {
                    CatalogueIconView(icon: currentGenmoji, color: tint, size: 24)
                }
            }
        }
        .buttonStyle(.plain)
        .background {
            EmojiInput(focusRequest: emojiKeyboardRequest, onPick: choose)
                .frame(width: 1, height: 1)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    /// Shown in the Any Emoji card, as the shortlist can't show it.
    private var currentGenmoji: CatalogueIcon? {
        if case .genmoji = selection { return selection }
        return nil
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoSection: some View {
        if case .photo = selection, let selection {
            CatalogueIconView(icon: selection, color: tint, size: 0, tileCornerRadius: 24)
                .frame(width: 120, height: 120)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Current Photo")
        }

        // Read out here: the label closure is nonisolated.
        let loading = isLoadingPhoto
        let tint = tint
        VStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ActionCard(
                    systemImage: loading ? "hourglass" : "photo.on.rectangle",
                    title: loading ? "Loading…" : "Choose Photo",
                    subtitle: "Cropped to a square",
                    tint: tint
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPhoto)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }

#if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(action: openCamera) {
                    ActionCard(systemImage: "camera", title: "Take Photo", tint: tint)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPhoto)
                .background(CameraPresentationAnchor(coordinator: cameraCoordinator))
            }
#endif
        }
        .padding(.horizontal)
        .alert("Couldn't Use Photo", isPresented: $photoLoadFailed) {
            Button("OK") {}
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            photoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            photoLoadFailed = true
            return
        }
        await usePhoto(data)
    }

    /// Off the main actor: a camera original can be tens of megapixels.
    private func usePhoto(_ data: Data) async {
        let icon = await Task.detached { makeSquareIconData(from: data) }.value
        guard let icon else {
            photoLoadFailed = true
            return
        }
        choose(.photo(icon))
    }

#if os(iOS)
    private func openCamera() {
        // The button's CameraPresentationAnchor presents it.
        cameraCoordinator = CameraCoordinator(
            onCapture: { image in
                guard let data = image.jpegData(compressionQuality: 0.9) else { return }
                isLoadingPhoto = true
                Task {
                    await usePhoto(data)
                    isLoadingPhoto = false
                }
            },
            onDismiss: { cameraCoordinator = nil }
        )
    }
#endif

    // MARK: - Cell

    private func cell(systemImage: String, isSelected: Bool) -> some View {
        cell(isSelected: isSelected) {
            Image(systemName: systemImage).font(.title2)
        }
    }

    private func cell(isSelected: Bool, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: 60, height: 60)
            .background(isSelected ? tint.opacity(0.2) : Color.secondary.opacity(0.1))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint, lineWidth: 2)
                }
            }
    }
}

// MARK: - Action Card

// Nonisolated: the photo picker builds it in its nonisolated label closure.
nonisolated private struct ActionCard<Trailing: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let tint: Color
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(
                    .background,
                    in: .rect(cornerRadius: AppConstants.ItemCard.thumbnailCornerRadius, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(AppConstants.ItemCard.contentPadding)
        .frame(maxWidth: .infinity)
        .background(
            Color.secondary.opacity(0.1),
            in: .rect(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
        )
        .contentShape(.rect)
    }
}

nonisolated extension ActionCard where Trailing == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, tint: Color) {
        self.init(systemImage: systemImage, title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

// MARK: - Emoji Input

/// The first Genmoji in the text, else the first emoji. A Genmoji is U+FFFC carrying the glyph
/// as an attribute, which the emoji check skips.
private func pickedIcon(in text: NSAttributedString) -> CatalogueIcon? {
    var genmoji: NSAdaptiveImageGlyph?
    text.enumerateAttribute(.adaptiveImageGlyph, in: NSRange(location: 0, length: text.length)) { value, _, stop in
        if let glyph = value as? NSAdaptiveImageGlyph {
            genmoji = glyph
            stop.pointee = true
        }
    }
    if let genmoji { return .genmoji(genmoji.imageContent) }
    return text.string.first(where: \.isEmoji).map { .emoji(String($0)) }
}

#if os(iOS)
/// There is no public API to request the emoji keyboard, so the view overrides `textInputMode`
/// to ask for it. If the user has removed the emoji keyboard the override returns nil and the
/// default keyboard shows instead; typed or pasted emoji are picked up the same way. A text
/// view, not a field: only rich text accepts Genmoji.
private struct EmojiInput: UIViewRepresentable {
    /// Each increment focuses the view.
    let focusRequest: Int
    let onPick: (CatalogueIcon) -> Void

    func makeUIView(context: Context) -> EmojiTextView {
        let view = EmojiTextView()
        view.supportsAdaptiveImageGlyph = true
        view.delegate = context.coordinator
        context.coordinator.handledRequest = focusRequest
        return view
    }

    func updateUIView(_ view: EmojiTextView, context: Context) {
        context.coordinator.onPick = onPick
        guard context.coordinator.handledRequest != focusRequest else { return }
        context.coordinator.handledRequest = focusRequest
        view.becomeFirstResponder()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onPick: (CatalogueIcon) -> Void
        var handledRequest = 0

        init(onPick: @escaping (CatalogueIcon) -> Void) { self.onPick = onPick }

        // On change, not submit: the emoji keyboard has no return key.
        func textViewDidChange(_ textView: UITextView) {
            guard let icon = pickedIcon(in: textView.attributedText) else { return }
            textView.text = ""
            textView.resignFirstResponder()
            onPick(icon)
        }
    }

    final class EmojiTextView: UITextView {
        override var textInputMode: UITextInputMode? {
            UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
        }
    }
}
#else
/// Receives what the Character Viewer inserts. A text view, not a field: only rich text
/// accepts Genmoji.
private struct EmojiInput: NSViewRepresentable {
    /// Each increment focuses the view and opens the Character Viewer.
    let focusRequest: Int
    let onPick: (CatalogueIcon) -> Void

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isRichText = true
        view.supportsAdaptiveImageGlyph = true
        view.drawsBackground = false
        view.delegate = context.coordinator
        context.coordinator.handledRequest = focusRequest
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.onPick = onPick
        guard context.coordinator.handledRequest != focusRequest else { return }
        context.coordinator.handledRequest = focusRequest
        view.window?.makeFirstResponder(view)
        NSApp.orderFrontCharacterPalette(nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onPick: (CatalogueIcon) -> Void
        var handledRequest = 0

        init(onPick: @escaping (CatalogueIcon) -> Void) { self.onPick = onPick }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView,
                  let icon = pickedIcon(in: view.attributedString()) else { return }
            view.string = ""
            onPick(icon)
        }
    }
}
#endif

#Preview("Icon Picker") {
    IconPickerView(selectedIcon: .constant(.symbol("star.fill")))
}

#Preview("Optional Icon Picker") {
    IconPickerView(optionalIcon: .constant(nil))
}
