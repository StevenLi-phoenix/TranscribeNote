import SwiftUI
import os

struct SettingsView: View {
    var body: some View {
        TabView {
            ModelsSettingsTab()
                .tabItem { Label("Models", systemImage: "cpu") }

            LLMAssignmentTab()
                .tabItem { Label("LLM", systemImage: "brain") }

            SummarizationSettingsTab()
                .tabItem { Label("Summarization", systemImage: "text.badge.star") }

            RecordingSettingsTab()
                .tabItem { Label("Recording", systemImage: "mic") }
        }
        .frame(width: 500, height: 500)
    }
}

// MARK: - Models Tab (define named LLM profiles)

struct ModelsSettingsTab: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "ModelsSettingsTab")

    @AppStorage("hasShownPrivacyDisclosure") private var hasShownDisclosure = false
    @State private var showPrivacySheet = false
    @State private var profiles: [LLMModelProfile] = []
    @State private var selectedProfileID: UUID?
    @State private var hasUnsavedChanges = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var connectionError: String?
    @State private var connectionTask: Task<Void, Never>?

    enum ConnectionStatus {
        case unknown, testing, available, unavailable
    }

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
                        VStack(alignment: .leading, spacing: 2) {
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
                        TextField("Profile Name", text: binding.name)
                            .textFieldStyle(.roundedBorder)
                            .font(DS.Typography.body)

                        LLMConfigSection(
                            title: nil,
                            subtitle: nil,
                            config: binding.config
                        )

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

                            connectionStatusView
                        }
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
        .onAppear {
            if !hasShownDisclosure {
                showPrivacySheet = true
            }
            loadProfiles()
        }
        .onChange(of: profiles) { _, _ in hasUnsavedChanges = true }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyDisclosureView {
                hasShownDisclosure = true
                showPrivacySheet = false
            }
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .unknown: EmptyView()
        case .testing: ProgressView().controlSize(.small)
        case .available: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                if let connectionError {
                    Text(connectionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

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

    private func testConnection(config: LLMConfig) {
        connectionTask?.cancel()
        connectionStatus = .testing
        connectionError = nil
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

// MARK: - LLM Assignment Tab (assign models to roles)

struct LLMAssignmentTab: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "LLMAssignmentTab")

    @State private var profiles: [LLMModelProfile] = []
    @State private var liveProfileID: UUID?
    @State private var overallProfileID: UUID?
    @State private var titleProfileID: UUID?
    @State private var overallInheritsLive = false
    @State private var titleInheritsLive = true

    var body: some View {
        Form {
            // Live
            Section {
                profilePicker(selection: $liveProfileID)
            } header: {
                sectionHeader(title: "Live Summarization", subtitle: "Periodic summarization during recording")
            }

            Divider()

            // Overall
            Section {
                Toggle("Use Live Model", isOn: $overallInheritsLive)
                if !overallInheritsLive {
                    profilePicker(selection: $overallProfileID)
                }
            } header: {
                sectionHeader(title: "Overall Summary", subtitle: "Post-recording complete summary")
            }

            Divider()

            // Title
            Section {
                Toggle("Use Live Model", isOn: $titleInheritsLive)
                if !titleInheritsLive {
                    profilePicker(selection: $titleProfileID)
                }
            } header: {
                sectionHeader(title: "Title Generation", subtitle: "Auto-generate session titles after recording")
            }
        }
        .padding()
        .onAppear { loadAssignments() }
        .onChange(of: liveProfileID) { _, newValue in
            if let id = newValue { LLMProfileStore.setAssignedProfileID(id, for: .live) }
        }
        .onChange(of: overallProfileID) { _, newValue in
            if let id = newValue { LLMProfileStore.setAssignedProfileID(id, for: .overall) }
        }
        .onChange(of: titleProfileID) { _, newValue in
            if let id = newValue { LLMProfileStore.setAssignedProfileID(id, for: .title) }
        }
        .onChange(of: overallInheritsLive) { _, newValue in
            LLMProfileStore.setInheritsLive(newValue, for: .overall)
        }
        .onChange(of: titleInheritsLive) { _, newValue in
            LLMProfileStore.setInheritsLive(newValue, for: .title)
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Typography.sectionHeader)
            Text(subtitle)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func profilePicker(selection: Binding<UUID?>) -> some View {
        Picker("Model", selection: selection) {
            Text("None").tag(nil as UUID?)
            ForEach(profiles) { profile in
                Text("\(profile.name) (\(profile.config.model))")
                    .tag(profile.id as UUID?)
            }
        }
    }

    private func loadAssignments() {
        profiles = LLMProfileStore.loadProfiles()
        liveProfileID = LLMProfileStore.assignedProfileID(for: .live)
        overallProfileID = LLMProfileStore.assignedProfileID(for: .overall)
        titleProfileID = LLMProfileStore.assignedProfileID(for: .title)
        overallInheritsLive = LLMProfileStore.inheritsLive(for: .overall)
        titleInheritsLive = LLMProfileStore.inheritsLive(for: .title)
    }
}

// MARK: - Reusable LLM Config Section

struct LLMConfigSection: View {
    let title: String?
    let subtitle: String?
    @Binding var config: LLMConfig

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Typography.sectionHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Picker("Provider", selection: $config.provider) {
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: config.provider) { _, newProvider in
                config.baseURL = newProvider.defaultBaseURL
            }

            TextField("Model", text: $config.model)

            if config.provider == .openAI || config.provider == .anthropic {
                SecureField("API Key", text: $config.apiKey)
            }

            HStack {
                Text("Temperature")
                Slider(value: $config.temperature, in: 0...2, step: 0.1)
                Text(String(format: "%.1f", config.temperature))
                    .frame(width: 30)
                    .monospacedDigit()
            }

            HStack {
                Text("Max Tokens")
                Slider(
                    value: Binding(
                        get: { log2(Double(max(config.maxTokens, 256))) },
                        set: { config.maxTokens = 1 << Int($0.rounded()) }
                    ),
                    in: 8...17,
                    step: 1
                )
                Text("\(config.maxTokens)")
                    .frame(width: 60, alignment: .trailing)
                    .monospacedDigit()
            }

            Toggle("Enable Thinking", isOn: $config.thinkingEnabled)
                .help("Allow model to use extended thinking (e.g. Qwen3 <think> blocks). Disable to save tokens on simple tasks.")

            DisclosureGroup("Advanced") {
                TextField("Base URL", text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Summarization Settings Tab

struct SummarizationSettingsTab: View {
    private static let languageOptions: [(label: String, value: String)] = [
        ("Auto (match transcript)", "auto"),
        ("English", "English"),
        ("中文", "Chinese"),
        ("日本語", "Japanese"),
        ("한국어", "Korean"),
        ("Español", "Spanish"),
        ("Français", "French"),
        ("Deutsch", "German"),
        ("Custom...", "custom"),
    ]

    /// Built-in picker values (everything except "custom").
    private static let builtinValues: Set<String> = {
        Set(languageOptions.map(\.value).filter { $0 != "custom" })
    }()

    @AppStorage("summarizerConfigJSON") private var summarizerConfigJSON: String = ""
    @State private var config: SummarizerConfig = .default
    @State private var pickerSelection: String = "auto"
    @State private var customLanguage: String = ""

    var body: some View {
        Form {
            Toggle("Enable Live Summarization", isOn: $config.liveSummarizationEnabled)
                .help("Periodically summarize transcript during recording. Disable to save resources or if LLM is not configured.")

            Stepper("Summary Interval: \(config.intervalMinutes) min", value: $config.intervalMinutes, in: 1...30)
                .disabled(!config.liveSummarizationEnabled)

            Stepper("Min Transcript Length: \(config.minTranscriptLength)", value: $config.minTranscriptLength, in: 50...500, step: 50)

            Picker("Summary Style", selection: $config.summaryStyle) {
                Text("Bullet Points").tag(SummaryStyle.bullets)
                Text("Paragraph").tag(SummaryStyle.paragraph)
                Text("Action Items").tag(SummaryStyle.actionItems)
                Text("Lecture Notes").tag(SummaryStyle.lectureNotes)
            }

            Picker("Overall Summary Mode", selection: $config.overallSummaryMode) {
                Text("Auto (chunks if available)").tag(OverallSummaryMode.auto)
                Text("Raw Text (full transcript)").tag(OverallSummaryMode.rawText)
                Text("Chunk Summaries Only").tag(OverallSummaryMode.chunkSummaries)
            }
            .help("Controls whether overall summary is generated from raw transcript text or from existing chunk summaries.")

            Picker("Language", selection: $pickerSelection) {
                ForEach(Self.languageOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .onChange(of: pickerSelection) { _, newValue in
                if newValue == "custom" {
                    config.summaryLanguage = customLanguage.isEmpty ? "auto" : customLanguage
                } else {
                    config.summaryLanguage = newValue
                }
            }

            if pickerSelection == "custom" {
                TextField("Custom Language", text: $customLanguage)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customLanguage) { _, newValue in
                        config.summaryLanguage = newValue.isEmpty ? "auto" : newValue
                    }
            }

            Toggle("Include Previous Context", isOn: $config.includeContext)

            if config.includeContext {
                Stepper("Max Context Tokens: \(config.maxContextTokens)", value: $config.maxContextTokens, in: 500...5000, step: 500)
            }
        }
        .padding()
        .onAppear { loadConfig() }
        .onChange(of: config) { _, newValue in saveConfig(newValue) }
        .safeAreaInset(edge: .bottom) {
            Label("Changes take effect after restarting the app.", systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }

    private func loadConfig() {
        guard !summarizerConfigJSON.isEmpty,
              let data = summarizerConfigJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SummarizerConfig.self, from: data) else { return }
        config = decoded
        if Self.builtinValues.contains(decoded.summaryLanguage) {
            pickerSelection = decoded.summaryLanguage
        } else {
            pickerSelection = "custom"
            customLanguage = decoded.summaryLanguage
        }
    }

    private func saveConfig(_ config: SummarizerConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        summarizerConfigJSON = json
    }
}

// MARK: - Recording Settings Tab

struct RecordingSettingsTab: View {
    @AppStorage("vadConfigJSON") private var vadConfigJSON: String = ""
    @State private var config: VADConfig = .default

    var body: some View {
        Form {
            Toggle("Voice Activity Detection", isOn: $config.vadEnabled)
                .help("Skip feeding silence to ASR to save CPU. Audio is always recorded in full regardless of this setting.")

            HStack {
                Text("Silence Threshold")
                Slider(value: $config.silenceThreshold, in: 0.01...0.30, step: 0.01)
                Text(String(format: "%.2f", config.silenceThreshold))
                    .frame(width: 40)
                    .monospacedDigit()
            }
            .disabled(!config.vadEnabled)

            let autoStopEnabled = Binding<Bool>(
                get: { config.silenceTimeoutSeconds != nil },
                set: { config.silenceTimeoutSeconds = $0 ? 300 : nil }
            )
            Toggle("Auto-stop on silence", isOn: autoStopEnabled)
                .disabled(!config.vadEnabled)
                .help("Automatically stop recording after sustained silence.")

            if let timeout = config.silenceTimeoutSeconds {
                let timeoutBinding = Binding<Int>(
                    get: { timeout },
                    set: { config.silenceTimeoutSeconds = $0 }
                )
                Stepper("Timeout: \(timeout)s", value: timeoutBinding, in: 30...600, step: 30)
                    .disabled(!config.vadEnabled)
            }
        }
        .padding()
        .onAppear { loadConfig() }
        .onChange(of: config) { _, newValue in saveConfig(newValue) }
        .safeAreaInset(edge: .bottom) {
            Label("Changes take effect on next recording.", systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }

    private func loadConfig() {
        guard !vadConfigJSON.isEmpty,
              let data = vadConfigJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(VADConfig.self, from: data) else { return }
        config = decoded
    }

    private func saveConfig(_ config: VADConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        vadConfigJSON = json
    }
}

extension LLMProvider {
    var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }
}
