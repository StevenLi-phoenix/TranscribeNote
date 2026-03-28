import SwiftUI
import os

/// Settings tab for configuring the auto-export pipeline.
struct AutoExportSettingsTab: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "AutoExportSettingsTab"
    )

    @State private var config = AutoExportConfig.fromUserDefaults()

    var body: some View {
        SettingsGrid {
            SettingsRow("Auto-Export") {
                Toggle("", isOn: $config.isEnabled)
                    .labelsHidden()
                    .help("Automatically export after recording + summary complete")
            }

            if config.isEnabled {
                SettingsRow("Actions") {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ForEach(config.actions.indices, id: \.self) { index in
                            actionRow(at: index)
                        }

                        addActionMenu
                    }
                }

                if config.actions.isEmpty {
                    SettingsRow("") {
                        SettingsDescription("Add actions to run after each recording completes.")
                    }
                }
            }
        }
        .onChange(of: config) { _, newValue in
            newValue.saveToUserDefaults()
            Self.logger.debug("Auto-export config saved: enabled=\(newValue.isEnabled), actions=\(newValue.actions.count)")
        }
    }

    // MARK: - Action Row

    @ViewBuilder
    private func actionRow(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Image(systemName: config.actions[index].icon)
                    .foregroundStyle(.secondary)
                Text(config.actions[index].displayName)
                    .font(DS.Typography.callout)
                Spacer()
                Button(role: .destructive) {
                    config.actions.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove action")
            }

            actionConfig(at: index)
        }
        .padding(DS.Spacing.sm)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    @ViewBuilder
    private func actionConfig(at index: Int) -> some View {
        switch config.actions[index] {
        case .writeFile(let options):
            writeFileConfig(options: options, index: index)
        case .copyTranscript:
            SettingsDescription("Copies formatted transcript + summary to clipboard.")
        case .webhook(let options):
            webhookConfig(options: options, index: index)
        }
    }

    // MARK: - Write File Config

    @ViewBuilder
    private func writeFileConfig(options: WriteFileOptions, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text("Directory:")
                    .font(DS.Typography.caption)
                Text(options.directoryPath.isEmpty ? "Not set" : options.directoryPath)
                    .font(DS.Typography.caption)
                    .foregroundStyle(options.directoryPath.isEmpty ? .red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose...") {
                    chooseDirectory(for: index)
                }
                .controlSize(.small)
            }

            HStack {
                Text("Template:")
                    .font(DS.Typography.caption)
                TextField(
                    "Filename template",
                    text: Binding(
                        get: { options.filenameTemplate },
                        set: { config.actions[index] = .writeFile(WriteFileOptions(
                            directoryPath: options.directoryPath,
                            filenameTemplate: $0,
                            includeTranscript: options.includeTranscript,
                            includeSummary: options.includeSummary
                        )) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(DS.Typography.caption)
            }
            SettingsDescription("Available: {{title}}, {{date}}")
        }
    }

    // MARK: - Webhook Config

    @ViewBuilder
    private func webhookConfig(options: WebhookOptions, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text("URL:")
                    .font(DS.Typography.caption)
                TextField(
                    "https://example.com/webhook",
                    text: Binding(
                        get: { options.url },
                        set: { config.actions[index] = .webhook(WebhookOptions(
                            url: $0,
                            method: options.method,
                            includeTranscript: options.includeTranscript,
                            includeSummary: options.includeSummary,
                            secretHeader: options.secretHeader
                        )) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(DS.Typography.caption)
            }

            HStack {
                Text("Method:")
                    .font(DS.Typography.caption)
                Picker(
                    "",
                    selection: Binding(
                        get: { options.method },
                        set: { config.actions[index] = .webhook(WebhookOptions(
                            url: options.url,
                            method: $0,
                            includeTranscript: options.includeTranscript,
                            includeSummary: options.includeSummary,
                            secretHeader: options.secretHeader
                        )) }
                    )
                ) {
                    Text("POST").tag("POST")
                    Text("PUT").tag("PUT")
                }
                .labelsHidden()
                .fixedSize()
            }

            HStack {
                Text("Auth:")
                    .font(DS.Typography.caption)
                SecureField(
                    "Authorization header (optional)",
                    text: Binding(
                        get: { options.secretHeader },
                        set: { config.actions[index] = .webhook(WebhookOptions(
                            url: options.url,
                            method: options.method,
                            includeTranscript: options.includeTranscript,
                            includeSummary: options.includeSummary,
                            secretHeader: $0
                        )) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(DS.Typography.caption)
            }

            HStack(spacing: DS.Spacing.lg) {
                Toggle("Transcript", isOn: Binding(
                    get: { options.includeTranscript },
                    set: { config.actions[index] = .webhook(WebhookOptions(
                        url: options.url,
                        method: options.method,
                        includeTranscript: $0,
                        includeSummary: options.includeSummary,
                        secretHeader: options.secretHeader
                    )) }
                ))
                .font(DS.Typography.caption)

                Toggle("Summary", isOn: Binding(
                    get: { options.includeSummary },
                    set: { config.actions[index] = .webhook(WebhookOptions(
                        url: options.url,
                        method: options.method,
                        includeTranscript: options.includeTranscript,
                        includeSummary: $0,
                        secretHeader: options.secretHeader
                    )) }
                ))
                .font(DS.Typography.caption)
            }
        }
    }

    // MARK: - Add Action Menu

    private var addActionMenu: some View {
        Menu {
            Button {
                config.actions.append(.writeFile(WriteFileOptions()))
            } label: {
                Label("Write to File", systemImage: "doc.text")
            }
            Button {
                config.actions.append(.copyTranscript)
            } label: {
                Label("Copy Transcript", systemImage: "doc.on.clipboard")
            }
            Button {
                config.actions.append(.webhook(WebhookOptions()))
            } label: {
                Label("Send Webhook", systemImage: "arrow.up.forward.app")
            }
        } label: {
            Label("Add Action", systemImage: "plus.circle")
                .font(DS.Typography.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Directory Picker

    private func chooseDirectory(for index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose export directory"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            if case .writeFile(var options) = config.actions[index] {
                options.directoryPath = url.path
                config.actions[index] = .writeFile(options)
            }
        }
    }
}
