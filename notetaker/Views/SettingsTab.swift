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
        SettingsGrid {
            SettingsRow("Live Model") {
                profilePicker(selection: $liveProfileID)
                    .help("Model for periodic summarization during recording")
            }

            SettingsRow("Overall: Use Live") {
                Toggle("", isOn: $overallInheritsLive)
                    .labelsHidden()
                    .help("Reuse the live model for post-recording summary")
            }

            if !overallInheritsLive {
                SettingsRow("Overall Model") {
                    profilePicker(selection: $overallProfileID)
                }
            }

            SettingsRow("Title: Use Live") {
                Toggle("", isOn: $titleInheritsLive)
                    .labelsHidden()
                    .help("Reuse the live model for title generation")
            }

            if !titleInheritsLive {
                SettingsRow("Title Model") {
                    profilePicker(selection: $titleProfileID)
                }
            }
        }
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

    private func profilePicker(selection: Binding<UUID?>) -> some View {
        Picker("", selection: selection) {
            Text("None").tag(nil as UUID?)
            ForEach(profiles) { profile in
                Text("\(profile.name) (\(profile.config.model))")
                    .tag(profile.id as UUID?)
            }
        }
        .labelsHidden()
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
        SettingsGrid {
            SettingsRow("Live Summarization") {
                Toggle("", isOn: $config.liveSummarizationEnabled)
                    .labelsHidden()
                    .help("Periodically summarize transcript during recording.")
            }

            SettingsRow("Summary Interval") {
                Stepper(value: $config.intervalMinutes, in: 1...30) {
                    Text("\(config.intervalMinutes) min")
                        .monospacedDigit()
                }
                .disabled(!config.liveSummarizationEnabled)
            }

            SettingsRow("Min Transcript Length") {
                Stepper(value: $config.minTranscriptLength, in: 50...500, step: 50) {
                    Text("\(config.minTranscriptLength)")
                        .monospacedDigit()
                }
            }

            SettingsRow("Summary Style") {
                Picker("", selection: $config.summaryStyle) {
                    Text("Bullet Points").tag(SummaryStyle.bullets)
                    Text("Paragraph").tag(SummaryStyle.paragraph)
                    Text("Action Items").tag(SummaryStyle.actionItems)
                    Text("Lecture Notes").tag(SummaryStyle.lectureNotes)
                }
                .labelsHidden()
            }

            SettingsRow("Overall Summary Mode") {
                Picker("", selection: $config.overallSummaryMode) {
                    Text("Auto (chunks if available)").tag(OverallSummaryMode.auto)
                    Text("Raw Text (full transcript)").tag(OverallSummaryMode.rawText)
                    Text("Chunk Summaries Only").tag(OverallSummaryMode.chunkSummaries)
                }
                .labelsHidden()
            }

            SettingsRow("Language") {
                Picker("", selection: $pickerSelection) {
                    ForEach(Self.languageOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                .onChange(of: pickerSelection) { _, newValue in
                    if newValue == "custom" {
                        config.summaryLanguage = customLanguage.isEmpty ? "auto" : customLanguage
                    } else {
                        config.summaryLanguage = newValue
                    }
                }
            }

            if pickerSelection == "custom" {
                SettingsRow("Custom Language") {
                    TextField("", text: $customLanguage)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customLanguage) { _, newValue in
                            config.summaryLanguage = newValue.isEmpty ? "auto" : newValue
                        }
                }
            }

            SettingsRow("Auto-Extract Action Items") {
                Toggle("", isOn: $config.actionItemExtractionEnabled)
                    .labelsHidden()
                    .help("Automatically extract action items after recording ends.")
            }

            SettingsRow("Include Previous Context") {
                Toggle("", isOn: $config.includeContext)
                    .labelsHidden()
            }

            if config.includeContext {
                SettingsRow("Max Context Tokens") {
                    Stepper(value: $config.maxContextTokens, in: 500...5000, step: 500) {
                        Text("\(config.maxContextTokens)")
                            .monospacedDigit()
                    }
                }
            }
        }
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
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled: Bool = true
    @State private var config: VADConfig = .default

    var body: some View {
        SettingsGrid {
            SettingsRow("Sound Effects") {
                Toggle("", isOn: $soundEffectsEnabled)
                    .labelsHidden()
                    .help("Play subtle sounds on recording start, pause, resume, and stop.")
            }

            SettingsRow("Voice Activity Detection") {
                Toggle("", isOn: $config.vadEnabled)
                    .labelsHidden()
                    .help("Skip feeding silence to ASR to save CPU. Audio is always recorded regardless.")
            }

            SettingsRow("Silence Threshold") {
                Stepper(value: Binding(
                    get: { Double(config.silenceThreshold) },
                    set: { config.silenceThreshold = Float($0) }
                ), in: 0.01...0.30, step: 0.01) {
                    Text(String(format: "%.2f", config.silenceThreshold))
                        .monospacedDigit()
                }
                .disabled(!config.vadEnabled)
            }

            SettingsRow("Auto-stop on Silence") {
                Toggle("", isOn: Binding(
                    get: { config.silenceTimeoutSeconds != nil },
                    set: { config.silenceTimeoutSeconds = $0 ? 300 : nil }
                ))
                .labelsHidden()
                .disabled(!config.vadEnabled)
                .help("Automatically stop recording after sustained silence.")
            }

            if let timeout = config.silenceTimeoutSeconds {
                SettingsRow("Silence Timeout") {
                    Stepper(value: Binding(
                        get: { timeout },
                        set: { config.silenceTimeoutSeconds = $0 }
                    ), in: 30...600, step: 30) {
                        Text("\(timeout)s")
                            .monospacedDigit()
                    }
                    .disabled(!config.vadEnabled)
                }
            }
        }
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
