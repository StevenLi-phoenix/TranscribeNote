import SwiftUI
import os

// MARK: - LLM Assignment Tab (assign models to roles)

struct LLMAssignmentTab: View {
    @State private var profiles: [LLMModelProfile] = []
    @State private var liveProfileID: UUID?
    @State private var overallProfileID: UUID?
    @State private var titleProfileID: UUID?
    @State private var overallInheritsLive = false
    @State private var titleInheritsLive = true

    var body: some View {
        Form {
            Section {
                profilePicker(selection: $liveProfileID)
            } header: {
                sectionHeader(title: "Live Summarization", subtitle: "Periodic summarization during recording")
            }

            Divider()

            Section {
                Toggle("Use Live Model", isOn: $overallInheritsLive)
                if !overallInheritsLive {
                    profilePicker(selection: $overallProfileID)
                }
            } header: {
                sectionHeader(title: "Overall Summary", subtitle: "Post-recording complete summary")
            }

            Divider()

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
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title)
                .font(DS.Typography.sectionHeader)
            SettingsDescription(subtitle)
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
        .settingsFooter("Changes take effect after restarting the app.", icon: "arrow.clockwise")
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

            SettingsSlider("Silence Threshold", value: $config.silenceThreshold, in: 0.01...0.30, step: 0.01, format: "%.2f")
                .disabled(!config.vadEnabled)

            let autoStopEnabled = Binding<Bool>(
                get: { config.silenceTimeoutSeconds != nil },
                set: { config.silenceTimeoutSeconds = $0 ? 300 : nil }
            )
            Toggle("Auto-stop on silence", isOn: autoStopEnabled)
                .disabled(!config.vadEnabled)
                .help("Automatically stop recording after sustained silence.")

            if let timeout = config.silenceTimeoutSeconds {
                Stepper("Timeout: \(timeout)s", value: Binding(
                    get: { timeout },
                    set: { config.silenceTimeoutSeconds = $0 }
                ), in: 30...600, step: 30)
                    .disabled(!config.vadEnabled)
            }
        }
        .padding()
        .onAppear { loadConfig() }
        .onChange(of: config) { _, newValue in saveConfig(newValue) }
        .settingsFooter("Changes take effect on next recording.", icon: "arrow.clockwise")
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
