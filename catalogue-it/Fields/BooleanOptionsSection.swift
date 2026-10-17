//
//  BooleanOptionsSection.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Boolean Options Section

/// Shown for every Yes/No field whatever its display role, so one promoted to a role later
/// already has its labels and appearance.
struct BooleanOptionsSection: View {
    @Binding var options: BooleanOptions

    @State private var showingIconPicker = false

    /// `FieldDefinition.statusTabLabels`' fallback, so the placeholder is what renders.
    private var truePlaceholder: String { String(localized: "Yes") }
    private var falsePlaceholder: String { String(localized: "No") }

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

        Section {
            Button {
                showingIconPicker = true
            } label: {
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
                // ColorPicker can't represent "unset".
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
