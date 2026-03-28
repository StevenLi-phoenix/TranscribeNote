import SwiftUI
import os

// MARK: - Models Tab (define named LLM profiles)

struct ModelsSettingsTab: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "ModelsSettingsTab")

    @State private var profiles: [LLMModelProfile] = []
    @State private var selectedProfileID: UUID?
    @State private var hasUnsavedChanges = false
    @State private var connectionStatus: StatusIndicator.Status = .unknown
    @State private var connectionError: String?
    @State private var connectionTask: Task<Void, Never>?

    private var selectedProfile: Binding<LLMModelProfile>? {
        guard let id = selectedProfileID,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        return $profiles[index]
    }

    var body: some View {
        HSplitView {
            // Profile list (sidebar)
            VStack(spacing: 0) {
                List(selection: $selectedProfileID) {
                    ForEach(profiles) { profile in
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(profile.name)
                                .font(DS.Typography.body)
                            Text(profile.config.provider.displayName)
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(profile.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: DS.Spacing.sm) {
                    Button {
                        addProfile()
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        if let id = selectedProfileID {
                            deleteProfile(id: id)
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedProfileID == nil || profiles.count <= 1)

                    Spacer()
                }
                .padding(DS.Spacing.xs)
            }
            .frame(minWidth: 140, maxWidth: 180)

            // Profile editor (detail)
            if let binding = selectedProfile {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        recommendationSection(for: binding)

                        Form {
                            TextField("Name", text: binding.name)

                            LLMConfigSection(config: binding.config)

                            HStack {
                                Button("Save") {
                                    saveProfiles()
                                    NotificationCenter.default.post(name: .llmConfigDidSave, object: nil)
                                    hasUnsavedChanges = false
                                }
                                .disabled(!hasUnsavedChanges)
                                .buttonStyle(.borderedProminent)

                                Button("Test Connection") {
                                    testConnection(config: binding.wrappedValue.config)
                                }

                                StatusIndicator(connectionStatus, error: connectionError)
                            }
                        }
                        .formStyle(.columns)
                        .toggleStyle(.switch)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select a Model",
                    systemImage: "cpu",
                    description: Text("Choose a model profile from the list or add a new one")
                )
            }
        }
        .onAppear { loadProfiles() }
        .onChange(of: profiles) { _, _ in hasUnsavedChanges = true }
    }

    // MARK: - Profile CRUD

    private func loadProfiles() {
        profiles = LLMProfileStore.loadProfiles()
        if selectedProfileID == nil, let first = profiles.first {
            selectedProfileID = first.id
        }
        hasUnsavedChanges = false
    }

    private func saveProfiles() {
        LLMProfileStore.saveProfiles(profiles)
        Self.logger.info("Saved \(profiles.count) model profiles")
    }

    private func addProfile() {
        let profile = LLMModelProfile(name: "New Model", config: .default)
        profiles.append(profile)
        selectedProfileID = profile.id
    }

    private func deleteProfile(id: UUID) {
        LLMProfileStore.deleteProfile(id: id, from: &profiles)
        selectedProfileID = profiles.first?.id
    }

    // MARK: - Model Recommendations

    private func recommendationSection(for binding: Binding<LLMModelProfile>) -> some View {
        DisclosureGroup("Recommended for Your Mac") {
            let hw = ModelRecommendation.detectHardware()
            Text("\(hw.processorDescription) \u{00B7} \(hw.totalMemoryGB)GB RAM")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, DS.Spacing.xs)

            ForEach(ModelRecommendation.recommendedModels()) { model in
                HStack {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text(model.name).fontWeight(.medium)
                            Text(model.tier.rawValue)
                                .font(DS.Typography.caption2)
                                .padding(.horizontal, DS.Spacing.xs)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }
                        Text(model.description)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Apply") {
                        applyRecommendation(model, to: binding)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, DS.Spacing.xxs)
            }
        }
    }

    private func applyRecommendation(_ model: ModelRecommendation.RecommendedModel, to binding: Binding<LLMModelProfile>) {
        binding.wrappedValue.config.provider = model.provider
        binding.wrappedValue.config.model = model.modelID
        binding.wrappedValue.config.baseURL = model.baseURL
        Self.logger.info("Applied recommendation: \(model.name) (\(model.modelID))")
    }

    // MARK: - Connection Testing

    private func testConnection(config: LLMConfig) {
        connectionTask?.cancel()
        connectionStatus = .testing
        connectionError = nil

        // Foundation Models: just check availability, no network call needed
        if config.provider == .foundationModels {
            let available = FoundationModelsEngine.isModelAvailable
            connectionStatus = available ? .available : .unavailable
            if !available { connectionError = "Apple Intelligence not available on this device" }
            Self.logger.info("Foundation Models availability: \(available)")
            return
        }

        let engine = LLMEngineFactory.create(from: config)
        let cfg = config
        connectionTask = Task {
            do {
                let testMessages = [LLMMessage(role: .user, content: "Reply with exactly: OK")]
                let result = try await engine.generate(messages: testMessages, config: cfg)
                guard !Task.isCancelled else { return }
                let ok = !result.content.isEmpty
                connectionStatus = ok ? .available : .unavailable
                if !ok { connectionError = "Empty response" }
                Self.logger.info("LLM test: \(ok ? "success" : "empty") (\(result.content.count) chars)")
            } catch {
                guard !Task.isCancelled else { return }
                connectionStatus = .unavailable
                connectionError = error.localizedDescription
                Self.logger.error("LLM test failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Reusable LLM Config Section

struct LLMConfigSection: View {
    @Binding var config: LLMConfig

    var body: some View {
        Picker("Provider", selection: $config.provider) {
            ForEach(LLMProvider.allCases, id: \.self) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .onChange(of: config.provider) { _, newProvider in
            config.baseURL = newProvider.defaultBaseURL
        }

        if config.provider == .foundationModels {
            SettingsInfoLabel("Uses Apple's on-device model. No API key or network needed.", icon: "apple.intelligence")
        }

        if config.provider != .foundationModels {
            TextField("Model", text: $config.model)
        }

        if config.provider == .openAI || config.provider == .anthropic {
            SecureField("API Key", text: $config.apiKey)
        }

        if config.provider != .foundationModels {
            SettingsSlider("Temperature", value: $config.temperature, in: 0...2, step: 0.1, format: "%.1f", valueWidth: 30)

            SettingsIntSlider("Max Tokens", value: $config.maxTokens, logRange: 8...17)

            Toggle("Enable Thinking", isOn: $config.thinkingEnabled)
                .help("Allow model to use extended thinking (e.g. Qwen3 <think> blocks). Disable to save tokens on simple tasks.")

            DisclosureGroup("Advanced") {
                TextField("Base URL", text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typography.caption)
            }
        }
    }
}
