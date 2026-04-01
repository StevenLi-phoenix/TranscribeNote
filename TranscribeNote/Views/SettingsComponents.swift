import SwiftUI

// MARK: - SettingsDescription

/// Caption text for describing a setting. Replaces repeated `.font(DS.Typography.caption).foregroundStyle(.secondary)`.
struct SettingsDescription: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
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
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let valueWidth: CGFloat

    init(
        _ label: LocalizedStringKey,
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
        _ label: LocalizedStringKey,
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
    let label: LocalizedStringKey
    @Binding var value: Int
    let logRange: ClosedRange<Double>
    let valueWidth: CGFloat

    init(_ label: LocalizedStringKey, value: Binding<Int>, logRange: ClosedRange<Double>, valueWidth: CGFloat = 60) {
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
            Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Colors.success)
        case .unavailable:
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Colors.error)
                if let error {
                    Text(error)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.error)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - SettingsFooter

/// Bottom info bar for settings forms. Replaces repeated `.safeAreaInset { Label(...).font.foregroundStyle }`.
private struct SettingsFooterModifier: ViewModifier {
    let text: LocalizedStringKey
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
    func settingsFooter(_ text: LocalizedStringKey, icon: String) -> some View {
        modifier(SettingsFooterModifier(text: text, icon: icon))
    }
}

// MARK: - SettingsGrid

/// Scrollable container for SettingsRow items. Provides consistent vertical spacing and toggle style.
struct SettingsGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                content
            }
            .toggleStyle(.switch)
            .padding()
        }
    }
}

// MARK: - GoldenRatioColumns (Layout)

/// Custom Layout that splits two children at the golden ratio (38.2% : 61.8%).
/// Label is right-aligned in the left column; control is left-aligned in the right column.
/// Height is determined by the taller child — works correctly inside ScrollView.
private struct GoldenRatioColumns: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let total = proposal.width ?? 0
        let labelW = (total - spacing) * 0.382
        let controlW = (total - spacing) * 0.618
        let h0 = subviews[0].sizeThatFits(.init(width: labelW, height: nil)).height
        let h1 = subviews[1].sizeThatFits(.init(width: controlW, height: nil)).height
        return .init(width: total, height: max(h0, h1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let labelW = (bounds.width - spacing) * 0.382
        let controlW = (bounds.width - spacing) * 0.618
        let s0 = subviews[0].sizeThatFits(.init(width: labelW, height: nil))
        let s1 = subviews[1].sizeThatFits(.init(width: controlW, height: nil))
        // Label: right-aligned in left column, vertically centered
        subviews[0].place(
            at: .init(x: bounds.minX + labelW - s0.width, y: bounds.midY - s0.height / 2),
            proposal: .init(width: labelW, height: s0.height)
        )
        // Control: left-aligned in right column, vertically centered
        subviews[1].place(
            at: .init(x: bounds.minX + labelW + spacing, y: bounds.midY - s1.height / 2),
            proposal: .init(width: controlW, height: s1.height)
        )
    }
}

// MARK: - SettingsRow

/// Two-column settings row: label (38.2%) | control (61.8%) — golden ratio split.
/// Column divider is always at the same position regardless of label length.
struct SettingsRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        GoldenRatioColumns(spacing: DS.Spacing.md) {
            Text(label)
            content
        }
    }
}

// MARK: - SettingsInfoLabel

/// Label with icon for informational notes in settings. Uses caption styling with secondary color.
struct SettingsInfoLabel: View {
    let text: LocalizedStringKey
    let icon: String

    init(_ text: LocalizedStringKey, icon: String) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        Label(text, systemImage: icon)
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
    }
}
