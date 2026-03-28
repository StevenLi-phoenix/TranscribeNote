import SwiftUI

/// Sheet displayed before recording starts, letting the user choose a meeting template.
struct TemplatePickerView: View {
    let onSelect: (MeetingTemplate?) -> Void
    @State private var templates: [MeetingTemplate] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Text("Choose a Template")
                .font(DS.Typography.title)

            Text("Select a meeting type to configure recording settings, or skip to use defaults.")
                .font(DS.Typography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: DS.Spacing.md)],
                spacing: DS.Spacing.md
            ) {
                ForEach(templates) { template in
                    TemplateCard(template: template) {
                        onSelect(template)
                        dismiss()
                    }
                }
            }

            HStack {
                Spacer()
                Button("Skip") {
                    onSelect(nil)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(minWidth: 500, minHeight: 300)
        .onAppear {
            templates = MeetingTemplateStore.loadTemplates()
        }
    }
}

// MARK: - TemplateCard

private struct TemplateCard: View {
    let template: MeetingTemplate
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DS.Spacing.sm) {
                Image(systemName: template.icon)
                    .font(.title)
                    .foregroundStyle(.blue)

                Text(template.name)
                    .font(DS.Typography.body)
                    .fontWeight(.medium)

                Text(template.description)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let duration = template.suggestedDurationMinutes {
                    Text("~\(duration) min")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Spacing.md)
            .background(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Template: \(template.name)")
    }
}
