import SwiftUI
import os

/// Settings tab for managing meeting templates (built-in and custom).
struct TemplateManagerView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "TemplateManagerView"
    )

    @State private var templates: [MeetingTemplate] = []
    @State private var selectedTemplateID: UUID?
    @State private var showDeleteConfirmation = false
    @AppStorage("showTemplatePickerOnRecord") private var showPickerOnRecord = true

    var body: some View {
        VStack(spacing: 0) {
            // Toggle for template picker on record
            HStack {
                Toggle("Show template picker when starting a recording", isOn: $showPickerOnRecord)
                    .font(DS.Typography.callout)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)

            Divider()

            HSplitView {
                templateList
                    .frame(minWidth: 200, idealWidth: 220)

                templateDetail
                    .frame(minWidth: 300)
            }
        }
        .onAppear {
            templates = MeetingTemplateStore.loadTemplates()
        }
    }

    // MARK: - Template List

    private var templateList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTemplateID) {
                Section("Built-in") {
                    ForEach(templates.filter(\.isBuiltIn)) { template in
                        templateRow(template)
                    }
                }
                if templates.contains(where: { !$0.isBuiltIn }) {
                    Section("Custom") {
                        ForEach(templates.filter { !$0.isBuiltIn }) { template in
                            templateRow(template)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: DS.Spacing.sm) {
                Button(action: addTemplate) {
                    Image(systemName: "plus")
                }
                .help("Add custom template")

                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "minus")
                }
                .disabled(selectedIsBuiltIn)
                .help("Delete selected template")

                if let selected = selectedTemplate {
                    Button(action: { duplicateSelected(selected) }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Duplicate template")
                }

                Spacer()
            }
            .padding(DS.Spacing.sm)
        }
        .confirmationDialog(
            "Delete this template?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
        }
    }

    private func templateRow(_ template: MeetingTemplate) -> some View {
        Label {
            Text(template.name)
                .lineLimit(1)
        } icon: {
            Image(systemName: template.icon)
        }
        .tag(template.id)
    }

    // MARK: - Template Detail

    @ViewBuilder
    private var templateDetail: some View {
        if let index = selectedTemplateIndex {
            let isBuiltIn = templates[index].isBuiltIn
            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    SettingsGrid {
                        SettingsRow("Name") {
                            TextField("Template name", text: $templates[index].name)
                                .disabled(isBuiltIn)
                        }

                        SettingsRow("Icon") {
                            TextField("SF Symbol name", text: $templates[index].icon)
                                .disabled(isBuiltIn)
                        }

                        SettingsRow("Description") {
                            TextField("Description", text: $templates[index].description, axis: .vertical)
                                .lineLimit(2...4)
                                .disabled(isBuiltIn)
                        }

                        SettingsRow("Summary Interval") {
                            OptionalIntField(
                                value: $templates[index].summaryIntervalMinutes,
                                placeholder: "Default",
                                suffix: "min"
                            )
                            .disabled(isBuiltIn)
                        }

                        SettingsRow("Summary Style") {
                            Picker("", selection: optionalStyleBinding(for: index)) {
                                Text("Default").tag(String?.none)
                                ForEach(SummaryStyle.allCases, id: \.rawValue) { style in
                                    Text(style.rawValue.capitalized).tag(Optional(style.rawValue))
                                }
                            }
                            .labelsHidden()
                            .disabled(isBuiltIn)
                        }

                        SettingsRow("Language") {
                            TextField("auto", text: optionalStringBinding(for: index, keyPath: \.language))
                                .disabled(isBuiltIn)
                        }

                        SettingsRow("Suggested Duration") {
                            OptionalIntField(
                                value: $templates[index].suggestedDurationMinutes,
                                placeholder: "None",
                                suffix: "min"
                            )
                            .disabled(isBuiltIn)
                        }
                    }

                    if isBuiltIn {
                        Text("Built-in templates are read-only. Duplicate to customize.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(DS.Spacing.md)
            }
            .onChange(of: templates) { _, _ in
                persistTemplates()
            }
        } else {
            ContentUnavailableView(
                "No Template Selected",
                systemImage: "doc.text",
                description: Text("Select a template from the list to view or edit.")
            )
        }
    }

    // MARK: - Helpers

    private var selectedTemplate: MeetingTemplate? {
        templates.first { $0.id == selectedTemplateID }
    }

    private var selectedIsBuiltIn: Bool {
        selectedTemplate?.isBuiltIn ?? true
    }

    private var selectedTemplateIndex: Int? {
        guard let id = selectedTemplateID else { return nil }
        return templates.firstIndex { $0.id == id }
    }

    private func addTemplate() {
        let template = MeetingTemplate(
            name: "New Template",
            icon: "doc.text",
            description: ""
        )
        templates.append(template)
        selectedTemplateID = template.id
        persistTemplates()
        Self.logger.info("Created new custom template: \(template.id)")
    }

    private func deleteSelected() {
        guard let id = selectedTemplateID else { return }
        MeetingTemplateStore.deleteTemplate(id: id, from: &templates)
        selectedTemplateID = nil
        persistTemplates()
        Self.logger.info("Deleted template: \(id)")
    }

    private func duplicateSelected(_ template: MeetingTemplate) {
        let copy = MeetingTemplateStore.duplicateTemplate(template)
        templates.append(copy)
        selectedTemplateID = copy.id
        persistTemplates()
        Self.logger.info("Duplicated template \(template.id) as \(copy.id)")
    }

    private func persistTemplates() {
        MeetingTemplateStore.saveTemplates(templates)
    }

    // MARK: - Bindings

    private func optionalStyleBinding(for index: Int) -> Binding<String?> {
        Binding(
            get: { templates[index].summaryStyle },
            set: { templates[index].summaryStyle = $0 }
        )
    }

    private func optionalStringBinding(for index: Int, keyPath: WritableKeyPath<MeetingTemplate, String?>) -> Binding<String> {
        Binding(
            get: { templates[index][keyPath: keyPath] ?? "" },
            set: { newValue in
                templates[index][keyPath: keyPath] = newValue.isEmpty ? nil : newValue
            }
        )
    }
}

// MARK: - OptionalIntField

/// A text field that binds to an optional Int, showing a placeholder when nil.
private struct OptionalIntField: View {
    @Binding var value: Int?
    let placeholder: String
    let suffix: String

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            TextField(placeholder, value: $value, format: .number)
                .frame(width: 80)
            Text(suffix)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}
