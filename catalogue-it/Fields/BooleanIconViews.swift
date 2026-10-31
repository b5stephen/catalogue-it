//
//  BooleanIconViews.swift
//  catalogue-it
//

import SwiftUI

// MARK: - Boolean Icon Image

/// A Yes/No field's icon, dimmed for the "off" value. Same glyph either way: many chosen symbols
/// are `.fill` names with no outline counterpart.
struct BooleanIconImage: View {
    let icon: String
    let color: Color?
    let isOn: Bool

    var body: some View {
        Image(systemName: icon)
            .symbolVariant(.fill)
            .foregroundStyle(isOn ? AnyShapeStyle(color ?? .accentColor) : AnyShapeStyle(.tertiary))
            .accessibilityHidden(true)
    }
}

// MARK: - Boolean Value Label

/// The item page's value for a Yes/No field with an icon.
struct BooleanValueLabel: View {
    let icon: String
    let color: Color?
    let isOn: Bool
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            BooleanIconImage(icon: icon, color: color, isOn: isOn)
            Text(text)
                .foregroundStyle(isOn ? .primary : .secondary)
        }
    }
}

// MARK: - Icon Toggle Style

/// The edit sheet's control for a Yes/No field with an icon: the whole row toggles, showing the
/// current label beside a filled (on) or dashed (off) tile. Still a switch to accessibility.
struct IconToggleStyle: ToggleStyle {
    let icon: String
    let color: Color?
    let options: BooleanOptions

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                configuration.label
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(options.label(for: configuration.isOn))
                    .font(.subheadline)
                    .foregroundStyle(configuration.isOn ? AnyShapeStyle(color ?? .accentColor) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                IconToggleTile(icon: icon, color: color, isOn: configuration.isOn)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
        .accessibilityValue(options.label(for: configuration.isOn))
    }
}

private struct IconToggleTile: View {
    let icon: String
    let color: Color?
    let isOn: Bool

    @ScaledMetric private var size: CGFloat = 32

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppConstants.CornerRadius.small, style: .continuous)
    }

    var body: some View {
        Image(systemName: icon)
            .symbolVariant(.fill)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: size, height: size)
            .background {
                if isOn {
                    shape.fill(color ?? .accentColor)
                } else {
                    shape.strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            }
            .animation(.snappy(duration: 0.15), value: isOn)
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Icon Toggle") {
    @Previewable @State var built = true
    @Previewable @State var favourite = false
    let options = BooleanOptions(trueLabel: "Built", falseLabel: "Not Built")

    Form {
        Toggle("Built", isOn: $built)
            .toggleStyle(IconToggleStyle(icon: "hammer.fill", color: Color(hex: "#2B7A3B"), options: options))
        Toggle("Favourite", isOn: $favourite)
            .toggleStyle(IconToggleStyle(icon: "star.fill", color: Color(hex: "#C08A00"), options: BooleanOptions()))
        LabeledContent("Built") {
            BooleanValueLabel(icon: "hammer.fill", color: Color(hex: "#2B7A3B"), isOn: true, text: "Built")
        }
    }
}
