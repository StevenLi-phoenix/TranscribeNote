import SwiftUI
import os

struct SettingsView: View {
    var body: some View {
        TabView {
            LLMSettingsTab()
                .tabItem { Label("LLM", systemImage: "brain") }

            SummarizationSettingsTab()
                .tabItem { Label("Summarization", systemImage: "text.badge.star") }
        }
        .frame(width: 450, height: 400)
    }
}

struct LLMSettingsTab: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "LLMSettingsTab")

    @AppStorage("llmConfigJSON") private var llmConfigJSON: String = ""
    @State private var config: LLMConfig = .default
    @State private var connectionStatus: ConnectionStatus = .unknown

    enum ConnectionStatus {
        case unknown, testing, available, unavailable
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
        .onAppear { loadConfig() }
        .onChange(of: config) { _, newValue in saveConfig(newValue) }
    }

    private func loadConfig() {
        guard !llmConfigJSON.isEmpty,
              let data = llmConfigJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(LLMConfig.self, from: data) else { return }
        config = decoded
    }

    private func saveConfig(_ config: LLMConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        llmConfigJSON = json
    }

    @State private var connectionTask: Task<Void, Never>?

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
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SummarizationSettingsTab")

    @AppStorage("summarizerConfigJSON") private var summarizerConfigJSON: String = ""
    @State private var config: SummarizerConfig = .default

    var body: some View {
        Form {
            Stepper("Summary Interval: \(config.intervalMinutes) min", value: $config.intervalMinutes, in: 1...30)

            Stepper("Min Transcript Length: \(config.minTranscriptLength)", value: $config.minTranscriptLength, in: 50...500, step: 50)

            Picker("Summary Style", selection: $config.summaryStyle) {
                Text("Bullet Points").tag(SummaryStyle.bullets)
                Text("Paragraph").tag(SummaryStyle.paragraph)
                Text("Action Items").tag(SummaryStyle.actionItems)
            }

            TextField("Language", text: $config.summaryLanguage)
                .textFieldStyle(.roundedBorder)

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
