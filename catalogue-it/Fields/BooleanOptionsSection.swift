//
//  BooleanOptionsSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Boolean Options Section

/// Form sections configuring a Yes/No field: what its two states are called, which one new
/// items start in, and how it looks when it's used as a filter toggle.
///
/// Peer of the "Number Options" and "Options" sections — it appears for every `.boolean`
/// field regardless of display role. Roles are chosen in the catalogue's Options section;
/// this is only about the field itself, so a field configured here can be promoted to the
/// tab bar or a filter toggle later with its labels and appearance already in place.
///
/// Lives in `FieldEditorView`, so adding and editing a Yes/No field offer exactly
/// the same capability.
struct BooleanOptionsSection: View {
    @Binding var options: BooleanOptions

    @State private var showingIconPicker = false

    /// Matches `FieldDefinition.statusTabLabels`' fallback, so the placeholder shows exactly
    /// what will render if the user leaves the field blank.
    private var truePlaceholder: String { String(localized: "Yes") }
    private var falsePlaceholder: String { String(localized: "No") }

    /// Mirrors `FieldDefinition.flagIconName` for a field that may not exist yet — the
    /// field editor configures appearance before anything is persisted.
    private var icon: String? {
        let name = options.flagIconName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    private var color: Color? {
        let hex = options.flagColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hex, !hex.isEmpty else { return nil }
        return Color(hex: hex)
    }

    var body: some View {
        Section {
            Picker("New Items Start As", selection: $options.defaultValue) {
                Text(options.trueLabel ?? truePlaceholder).tag(true)
                Text(options.falseLabel ?? falsePlaceholder).tag(false)
            }
        }

        Section("Labels") {
            TextField(truePlaceholder, text: Binding(
                get: { options.trueLabel ?? "" },
                set: { options.trueLabel = $0.isEmpty ? nil : $0 }
            ))
            TextField(falsePlaceholder, text: Binding(
                get: { options.falseLabel ?? "" },
                set: { options.falseLabel = $0.isEmpty ? nil : $0 }
            ))
        }

        // Several flags on one catalogue need to be told apart at a glance, so each picks its
        // own symbol and tint rather than all rendering as the same badge. Both are optional:
        // with no icon the field simply shows no badge.
        Section {
            Button {
                showingIconPicker = true
            } label: {
                // No row label — the section header already says "Icon", so the row is just
                // the current choice.
                HStack {
                    if let icon {
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(color ?? .accentColor)
                            .frame(width: 32, height: 32)
                            .background((color ?? .accentColor).opacity(0.15))
                            .clipShape(.rect(cornerRadius: 6))
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .accessibilityLabel("Icon")
            }
            .foregroundStyle(.primary)
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(optionalIcon: Binding(
                    get: { icon },
                    set: { options.flagIconName = $0 }
                ))
            }

            if let color {
                ColorPicker("Colour", selection: Binding(
                    get: { color },
                    set: { options.flagColorHex = $0.toHex() }
                ), supportsOpacity: false)
            } else {
                // ColorPicker can't represent "unset", so an absent colour is a button that
                // adopts one rather than a picker sitting on an arbitrary starting value.
                Button("Set Colour") {
                    options.flagColorHex = Color.accentColor.toHex()
                }
            }

            if icon != nil || color != nil {
                Button("Clear", role: .destructive) {
                    options.flagIconName = nil
                    options.flagColorHex = nil
                }
            }
        } header: {
            Text("Icon")
        }
    }
}

// MARK: - Preview

#Preview("Yes/No Options") {
    @Previewable @State var configured = BooleanOptions(
        trueLabel: "Owned",
        defaultValue: true,
        flagIconName: "star.fill",
        flagColorHex: "#FFCC00"
    )
    @Previewable @State var empty = BooleanOptions()

    return TabView {
        Form { BooleanOptionsSection(options: $empty) }
            .tabItem { Text("Unset") }
        Form { BooleanOptionsSection(options: $configured) }
            .tabItem { Text("Configured") }
    }
}
