import SwiftUI
import os

// MARK: - Models Tab (define named LLM profiles)

struct ModelsSettingsTab: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "ModelsSettingsTab")

    @State private var profiles: [LLMModelProfile] = []
    @State private var selectedProfileID: UUID?
    @State private var hasUnsavedChanges = false
    @State private var lastDeletedProfile: (profile: LLMModelProfile, index: Int)?
    @State private var connectionStatus: StatusIndicator.Status = .unknown
    @State private var connectionError: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var showDeleteConfirmation = false
    @State private var pendingKeychainDeletions: [String] = []
    /// In-memory dot cache seeded from persisted lastTestPassed on load.
    @State private var testStatusCache: [UUID: StatusIndicator.Status] = [:]

    private var selectedProfile: Binding<LLMModelProfile>? {
        guard let id = selectedProfileID,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        return $profiles[index]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Profile list (sidebar)
            VStack(spacing: 0) {
                List(selection: $selectedProfileID) {
                    ForEach(profiles) { profile in
                        HStack(spacing: DS.Spacing.sm) {
                            testDot(for: testStatusCache[profile.id, default: .unknown])
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(profile.name)
                                    .font(DS.Typography.sectionHeader)
                                Text(profile.config.provider.displayName)
                                    .font(DS.Typography.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, DS.Spacing.xs)
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
                    .buttonStyle(.borderless)

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedProfileID == nil || profiles.count <= 1)
                    .confirmationDialog(
                        "Delete \(profiles.first { $0.id == selectedProfileID }?.name ?? "profile")?",
                        isPresented: $showDeleteConfirmation
                    ) {
                        Button("Delete", role: .destructive) {
                            if let id = selectedProfileID {
                                deleteProfile(id: id)
                            }
                        }
                    }

                    Button {
                        undoDelete()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .disabled(lastDeletedProfile == nil)
                    .help(String(localized: "Undo last deletion"))

                    Spacer()
                }
                .padding(.vertical, DS.Spacing.md)
                .padding(.trailing, DS.Spacing.sm)
                .padding(.leading, DS.Spacing.lg)
            }
            .frame(minWidth: 140, idealWidth: 160, maxWidth: 200)

            Divider()

            // Profile editor (detail)
            if let binding = selectedProfile {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            LLMConfigSection(config: binding.config, name: binding.name)

                            LLMConfigAdvancedSection(config: binding.config, name: binding.name)

                            ProfileUsageView(profile: binding.wrappedValue)
                        }
                        .toggleStyle(.switch)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }

                    Divider()

                    HStack {
                        Button("Save") {
                            saveProfiles()
                            NotificationCenter.default.post(name: .llmConfigDidSave, object: nil)
                            hasUnsavedChanges = false
                        }
                        .disabled(!hasUnsavedChanges)
                        .buttonStyle(.borderedProminent)

                        Button("Test Connection") {
                            testConnection(profileID: binding.wrappedValue.id, config: binding.wrappedValue.config)
                        }

                        StatusIndicator(connectionStatus, error: connectionError)
                    }
                    .padding(DS.Spacing.md)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Select a Model",
                    systemImage: "cpu",
                    description: Text("Choose a model profile from the list or add a new one")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { loadProfiles() }
        .onChange(of: profiles) { _, _ in hasUnsavedChanges = true }
    }

    // MARK: - Profile CRUD

    private func loadProfiles() {
        profiles = LLMProfileStore.loadProfiles()
        if selectedProfileID == nil, let first = profiles.first {
            selectedProfileID = first.id
        }
        // Seed dot cache from persisted test results
        for profile in profiles {
            if let passed = profile.lastTestPassed {
                testStatusCache[profile.id] = passed ? .available : .unavailable
            }
        }
        hasUnsavedChanges = false
    }

    private func saveProfiles() {
        // Clean up Keychain entries for deleted profiles
        for key in pendingKeychainDeletions {
            KeychainService.delete(key: key)
        }
        pendingKeychainDeletions.removeAll()
        LLMProfileStore.saveProfiles(profiles)
        Self.logger.info("Saved \(profiles.count) model profiles")
    }

    private func addProfile() {
        let defaultConfig = LLMConfig.default
        let profile = LLMModelProfile(name: "\(defaultConfig.provider.displayName) \(defaultConfig.model)", config: defaultConfig)
        profiles.append(profile)
        selectedProfileID = profile.id
    }

    private func deleteProfile(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profile = profiles[index]
        lastDeletedProfile = (profile, index)
        // Stage Keychain deletion — will be committed on Save
        pendingKeychainDeletions.append(profile.keychainKey)
        profiles.remove(at: index)
        selectedProfileID = profiles.first?.id
    }

    private func undoDelete() {
        guard let deleted = lastDeletedProfile else { return }
        // Cancel the pending Keychain deletion
        pendingKeychainDeletions.removeAll { $0 == deleted.profile.keychainKey }
        let insertIndex = min(deleted.index, profiles.count)
        profiles.insert(deleted.profile, at: insertIndex)
        selectedProfileID = deleted.profile.id
        lastDeletedProfile = nil
    }

    // MARK: - Connection Testing

    private func testConnection(profileID: UUID, config: LLMConfig) {
        connectionTask?.cancel()
        connectionStatus = .testing
        connectionError = nil
        testStatusCache[profileID] = .testing

        // Foundation Models: just check availability, no network call needed
        if config.provider == .foundationModels {
            let available = FoundationModelsEngine.isModelAvailable
            let status: StatusIndicator.Status = available ? .available : .unavailable
            connectionStatus = status
            testStatusCache[profileID] = status
            if !available { connectionError = "Apple Intelligence not available on this device" }
            LLMProfileStore.recordTestResult(profileID: profileID, passed: available)
            loadProfiles()
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
                let status: StatusIndicator.Status = ok ? .available : .unavailable
                connectionStatus = status
                testStatusCache[profileID] = status
                if !ok { connectionError = "Empty response" }
                LLMProfileStore.recordTestResult(profileID: profileID, passed: ok)
                loadProfiles()
                Self.logger.info("LLM test: \(ok ? "success" : "empty") (\(result.content.count) chars)")
            } catch {
                guard !Task.isCancelled else { return }
                connectionStatus = .unavailable
                testStatusCache[profileID] = .unavailable
                connectionError = error.localizedDescription
                LLMProfileStore.recordTestResult(profileID: profileID, passed: false)
                loadProfiles()
                Self.logger.error("LLM test failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Sidebar Status Dot

private extension ModelsSettingsTab {
    @ViewBuilder
    func testDot(for status: StatusIndicator.Status) -> some View {
        switch status {
        case .unknown:
            Circle()
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.5)
                .frame(width: 8, height: 8)
        case .testing:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 8, height: 8)
        case .available:
            Circle()
                .fill(DS.Colors.success)
                .frame(width: 8, height: 8)
        case .unavailable:
            Circle()
                .fill(DS.Colors.error)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Profile Usage Stats View

private struct ProfileUsageView: View {
    let profile: LLMModelProfile

    private var hasAnyData: Bool {
        profile.totalRequests > 0 || profile.lastTestedAt != nil
    }

    var body: some View {
        if hasAnyData {
            Divider()

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Usage")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)

                if profile.totalRequests > 0 {
                    HStack(spacing: DS.Spacing.lg) {
                        statItem(label: "Requests", value: "\(profile.totalRequests)")
                        statItem(label: "Input", value: formatTokens(profile.totalInputTokens))
                        statItem(label: "Output", value: formatTokens(profile.totalOutputTokens))
                    }
                }

                if let testedAt = profile.lastTestedAt {
                    HStack(spacing: DS.Spacing.xs) {
                        Circle()
                            .fill(profile.lastTestPassed == true ? DS.Colors.success : DS.Colors.error)
                            .frame(width: 6, height: 6)
                        Text("Last tested \(testedAt.formatted(.relative(presentation: .named)))")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.Typography.callout)
                .monospacedDigit()
            Text(label)
                .font(DS.Typography.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Reusable LLM Config Section

struct LLMConfigSection: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "LLMConfigSection")

    @Binding var config: LLMConfig
    @Binding var name: String
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var useCustomModel = false
    @State private var showCustomProviderDisclaimer = false
    @AppStorage("hasShownCustomProviderDisclaimer") private var hasShownCustomProviderDisclaimer = false

    private func autoName() -> String {
        "\(config.provider.displayName) \(config.model)"
    }

    private func fetchModels() {
        guard config.provider != .foundationModels else { return }
        isFetchingModels = true
        let engine = LLMEngineFactory.create(from: config)
        let cfg = config
        Task {
            defer { isFetchingModels = false }
            do {
                let models = try await engine.listModels(config: cfg)
                availableModels = models
                useCustomModel = !models.contains(config.model) && !config.model.isEmpty
                Self.logger.info("Fetched \(models.count) models from \(cfg.provider.displayName)")
            } catch {
                availableModels = []
                useCustomModel = true
                Self.logger.warning("Failed to fetch models: \(error.localizedDescription)")
            }
        }
    }

    private let labelWidth: CGFloat = 80

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Spacing.md, verticalSpacing: DS.Spacing.sm) {
            GridRow {
                formLabel("Provider")
                Picker("", selection: $config.provider) {
                    ForEach(LLMProvider.availableProviders.filter { provider in
                        provider != .foundationModels || FoundationModelsEngine.isModelAvailable
                    }, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help(String(localized: "LLM service provider. Use Custom for OpenAI-compatible APIs like LM Studio."))
                .onChange(of: config.provider) { _, newProvider in
                    config.baseURL = newProvider.defaultBaseURL
                    config.model = newProvider.defaultModel
                    config.maxTokens = newProvider.defaultMaxTokens
                    name = autoName()
                    availableModels = []
                    useCustomModel = false
                    fetchModels()

                    if newProvider == .custom && LLMProvider.isChineseStorefront && !hasShownCustomProviderDisclaimer {
                        showCustomProviderDisclaimer = true
                    }
                }
                .onAppear { fetchModels() }
            }

            if config.provider == .foundationModels {
                SettingsInfoLabel("On-device model. No API key needed.", icon: "apple.intelligence")
                    .gridCellColumns(2)
            }

            if config.provider == .ollama {
                SettingsInfoLabel("Requires local Ollama installation.", icon: "desktopcomputer")
                    .gridCellColumns(2)
            }

            if let filingNumber = config.provider.filingNumber {
                HStack(spacing: DS.Spacing.xs) {
                    Text(filingNumber)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    if let filingURL = config.provider.filingURL {
                        Link("Verify", destination: filingURL)
                            .font(DS.Typography.caption)
                    }
                }
                .gridCellColumns(2)
            }

            if config.provider == .custom {
                GridRow {
                    formLabel("Base URL")
                    TextField("", text: $config.baseURL)
                        .help(String(localized: "API endpoint URL for your OpenAI-compatible service."))
                        .onSubmit { fetchModels() }
                }
            }

            if config.provider.requiresAPIKey {
                GridRow {
                    formLabel("API Key")
                    SecureField("", text: $config.apiKey)
                        .help(String(localized: "Stored securely in macOS Keychain. Never saved to disk in plaintext."))
                        .onSubmit { fetchModels() }
                }
            }

            if config.provider != .foundationModels {
                GridRow {
                    formLabel("Model")
                    HStack {
                        if useCustomModel || availableModels.isEmpty {
                            TextField("", text: $config.model)
                                .help(String(localized: "Model identifier, e.g. gpt-4o, claude-sonnet-4-20250514, qwen3.5-9b-mlx."))
                        } else {
                            Picker("", selection: $config.model) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                            .help(String(localized: "Select a model from the server."))
                        }

                        if !availableModels.isEmpty {
                            Button {
                                useCustomModel.toggle()
                            } label: {
                                Image(systemName: useCustomModel ? "list.bullet" : "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help(useCustomModel ? String(localized: "Choose from available models") : String(localized: "Enter custom model name"))
                        }

                        Button {
                            fetchModels()
                        } label: {
                            if isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isFetchingModels)
                        .help(String(localized: "Fetch available models from the server"))
                    }
                    .onChange(of: config.model) { _, _ in
                        name = autoName()
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomProviderDisclaimer) {
            CustomProviderDisclaimerView {
                hasShownCustomProviderDisclaimer = true
                showCustomProviderDisclaimer = false
            }
        }
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: labelWidth, alignment: .leading)
    }
}

// MARK: - Advanced Settings (separate Form to prevent label-column width shift)

struct LLMConfigAdvancedSection: View {
    @Binding var config: LLMConfig
    @Binding var name: String
    @State private var isExpanded = false

    private let labelWidth: CGFloat = 80

    var body: some View {
        if config.provider != .foundationModels {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text("Advanced")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Spacing.md, verticalSpacing: DS.Spacing.sm) {
                        GridRow {
                            formLabel("Name")
                            TextField("", text: $name)
                                .help(String(localized: "Custom display name. Auto-generated from provider and model by default."))
                        }

                        SettingsSlider("Temperature", value: $config.temperature, in: 0...2, step: 0.1, format: "%.1f", valueWidth: 30)
                            .help(String(localized: "Controls randomness. Lower = more focused, higher = more creative."))
                            .gridCellColumns(2)

                        SettingsIntSlider("Max Tokens", value: $config.maxTokens, logRange: 8...14)
                            .help(String(localized: "Maximum number of tokens in the generated response."))
                            .gridCellColumns(2)

                        GridRow {
                            formLabel("Thinking")
                            Toggle("", isOn: $config.thinkingEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .help(String(localized: "Allow model to use extended thinking."))
                        }

                        if config.provider != .custom {
                            GridRow {
                                formLabel("Base URL")
                                TextField("", text: $config.baseURL)
                                    .help(String(localized: "API endpoint URL. Change for self-hosted or proxy setups."))
                            }
                        }
                    }
                    .padding(.top, DS.Spacing.sm)
                }
            }
        }
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: labelWidth, alignment: .leading)
    }
}
