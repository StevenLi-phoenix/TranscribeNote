import SwiftUI

// MARK: - SettingsDescription

/// Caption text for describing a setting. Replaces repeated `.font(DS.Typography.caption).foregroundStyle(.secondary)`.
struct SettingsDescription: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - SettingsSlider

/// Slider with label and formatted value display. Replaces repeated `HStack { Text; Slider; Text.monospacedDigit() }`.
struct SettingsSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let valueWidth: CGFloat

    init(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 0.1,
        format: String = "%.1f",
        valueWidth: CGFloat = 40
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.valueWidth = valueWidth
    }

    init(
        _ label: String,
        value: Binding<Float>,
        in range: ClosedRange<Double>,
        step: Double = 0.1,
        format: String = "%.1f",
        valueWidth: CGFloat = 40
    ) {
        self.label = label
        self._value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = Float($0) }
        )
        self.range = range
        self.step = step
        self.format = format
        self.valueWidth = valueWidth
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(String(format: format, value))
                    .frame(width: valueWidth, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - SettingsIntSlider

/// Integer slider with logarithmic (base-2) scale. Used for values like Max Tokens where exponential steps make sense.
struct SettingsIntSlider: View {
    let label: String
    @Binding var value: Int
    let logRange: ClosedRange<Double>
    let valueWidth: CGFloat

    init(_ label: String, value: Binding<Int>, logRange: ClosedRange<Double>, valueWidth: CGFloat = 60) {
        self.label = label
        self._value = value
        self.logRange = logRange
        self.valueWidth = valueWidth
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(
                    value: Binding(
                        get: { log2(Double(max(value, 1 << Int(logRange.lowerBound)))) },
                        set: { value = 1 << Int($0.rounded()) }
                    ),
                    in: logRange,
                    step: 1
                )
                Text("\(value)")
                    .frame(width: valueWidth, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - StatusIndicator

/// Connection/availability status display with icon and optional error message.
struct StatusIndicator: View {
    enum Status {
        case unknown, testing, available, unavailable
    }

    let status: Status
    let error: String?

    init(_ status: Status, error: String? = nil) {
        self.status = status
        self.error = error
    }

    var body: some View {
        switch status {
        case .unknown:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .available:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable:
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                if let error {
                    Text(error)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - SettingsFooter

/// Bottom info bar for settings forms. Replaces repeated `.safeAreaInset { Label(...).font.foregroundStyle }`.
private struct SettingsFooterModifier: ViewModifier {
    let text: String
    let icon: String

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            Label(text, systemImage: icon)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, DS.Spacing.sm)
        }
    }
}

extension View {
    func settingsFooter(_ text: String, icon: String) -> some View {
        modifier(SettingsFooterModifier(text: text, icon: icon))
    }
}

// MARK: - SettingsGrid

/// Scrollable container for SettingsRow items. Provides consistent vertical spacing and toggle style.
struct SettingsGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                content
            }
            .toggleStyle(.switch)
            .padding()
        }
    }
}

// MARK: - SettingsRow

/// Two-column settings row: label (trailing, 50%) | control (leading, 50%).
/// All rows share the same 50/50 split — column divider is always at the center regardless of label length.
struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - SettingsInfoLabel

/// Label with icon for informational notes in settings. Uses caption styling with secondary color.
struct SettingsInfoLabel: View {
    let text: String
    let icon: String

    init(_ text: String, icon: String) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        Label(text, systemImage: icon)
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
    }
}
