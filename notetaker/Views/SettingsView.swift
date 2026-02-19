import SwiftUI
import os

struct SettingsView: View {
    var body: some View {
        TabView {
            LLMSettingsTab(configKey: "liveLLMConfigJSON")
                .tabItem { Label("Live LLM", systemImage: "brain") }

            LLMSettingsTab(configKey: "overallLLMConfigJSON")
                .tabItem { Label("Overall LLM", systemImage: "brain.head.profile") }

            SummarizationSettingsTab()
                .tabItem { Label("Summarization", systemImage: "text.badge.star") }
        }
        .frame(width: 450, height: 400)
    }
}

struct LLMSettingsTab: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "LLMSettingsTab")

    let configKey: String
    let fallbackKey: String
    @AppStorage private var configJSON: String
    @AppStorage("hasShownPrivacyDisclosure") private var hasShownDisclosure = false
    @State private var showPrivacySheet = false
    @State private var config: LLMConfig = .default
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var connectionTask: Task<Void, Never>?

    enum ConnectionStatus {
        case unknown, testing, available, unavailable
    }

    init(configKey: String, fallbackKey: String = "llmConfigJSON") {
        self.configKey = configKey
        self.fallbackKey = fallbackKey
        _configJSON = AppStorage(wrappedValue: "", configKey)
    }

    var body: some View {
        Form {
            Picker("Provider", selection: $config.provider) {
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            TextField("Model", text: $config.model)

            TextField("Base URL", text: $config.baseURL)
                .textFieldStyle(.roundedBorder)

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
                // Log2 slider: 2^8=256 to 2^17=131072
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

            HStack {
                Button("Test Connection") {
                    testConnection()
                }

                switch connectionStatus {
                case .unknown: EmptyView()
                case .testing: ProgressView().controlSize(.small)
                case .available: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .unavailable: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
        }
        .padding()
        .onAppear {
            if !hasShownDisclosure {
                showPrivacySheet = true
            }
            loadConfig()
        }
        .onChange(of: config) { _, newValue in saveConfig(newValue) }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyDisclosureView {
                hasShownDisclosure = true
                showPrivacySheet = false
            }
        }
    }

    private func loadConfig() {
        // Try primary key first
        if !configJSON.isEmpty,
           let data = configJSON.data(using: .utf8),
           var decoded = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            decoded.apiKey = KeychainService.load(key: LLMConfig.keychainKey(for: configKey)) ?? ""
            config = decoded
            return
        }
        // Fall back to legacy key
        let fallback = LLMConfig.fromUserDefaults(key: fallbackKey)
        config = fallback
    }

    private func saveConfig(_ config: LLMConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        configJSON = json
        KeychainService.save(key: LLMConfig.keychainKey(for: configKey), value: config.apiKey)
    }

    private func testConnection() {
        connectionTask?.cancel()
        connectionStatus = .testing
        let engine = LLMEngineFactory.create(from: config)
        let cfg = config
        connectionTask = Task {
            let available = await engine.isAvailable(config: cfg)
            guard !Task.isCancelled else { return }
            connectionStatus = available ? .available : .unavailable
            Self.logger.info("Connection test result: \(available ? "available" : "unavailable")")
        }
    }
}

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
            Stepper("Summary Interval: \(config.intervalMinutes) min", value: $config.intervalMinutes, in: 1...30)

            Stepper("Min Transcript Length: \(config.minTranscriptLength)", value: $config.minTranscriptLength, in: 50...500, step: 50)

            Picker("Summary Style", selection: $config.summaryStyle) {
                Text("Bullet Points").tag(SummaryStyle.bullets)
                Text("Paragraph").tag(SummaryStyle.paragraph)
                Text("Action Items").tag(SummaryStyle.actionItems)
                Text("Lecture Notes").tag(SummaryStyle.lectureNotes)
            }

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
    }

    private func loadConfig() {
        guard !summarizerConfigJSON.isEmpty,
              let data = summarizerConfigJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SummarizerConfig.self, from: data) else { return }
        config = decoded
        // Restore picker state from stored language
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
