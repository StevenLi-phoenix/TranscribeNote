import SwiftUI
import os

// MARK: - LLM Assignment Tab (assign models to roles)

struct LLMAssignmentTab: View {
    @State private var profiles: [LLMModelProfile] = []
    @State private var liveProfileID: UUID?
    @State private var overallProfileID: UUID?
    @State private var titleProfileID: UUID?
    @State private var chatProfileID: UUID?
    @State private var overallInheritsLive = false
    @State private var titleInheritsLive = true
    @State private var chatInheritsLive = true

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

            SettingsRow("Chat: Use Live") {
                Toggle("", isOn: $chatInheritsLive)
                    .labelsHidden()
                    .help("Reuse the live model for transcript chat")
            }

            if !chatInheritsLive {
                SettingsRow("Chat Model") {
                    profilePicker(selection: $chatProfileID)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: overallInheritsLive)
        .animation(.easeInOut(duration: 0.2), value: titleInheritsLive)
        .animation(.easeInOut(duration: 0.2), value: chatInheritsLive)
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
        .onChange(of: chatProfileID) { _, newValue in
            if let id = newValue { LLMProfileStore.setAssignedProfileID(id, for: .chat) }
        }
        .onChange(of: chatInheritsLive) { _, newValue in
            LLMProfileStore.setInheritsLive(newValue, for: .chat)
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
        chatProfileID = LLMProfileStore.assignedProfileID(for: .chat)
        chatInheritsLive = LLMProfileStore.inheritsLive(for: .chat)
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
                    Text("\(config.minTranscriptLength) chars")
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
        .animation(.easeInOut(duration: 0.2), value: pickerSelection == "custom")
        .animation(.easeInOut(duration: 0.2), value: config.includeContext)
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
    @AppStorage("skipTrashOnDelete") private var skipTrash = false
    @AppStorage("globalHotkeyEnabled") private var globalHotkeyEnabled = true
    @AppStorage("globalHotkeyKeyCode") private var hotkeyKeyCode = Int(GlobalHotkeyService.defaultKeyCode)
    @AppStorage("globalHotkeyModifiers") private var hotkeyModifiers = Int(GlobalHotkeyService.defaultModifiers)
    @State private var config: VADConfig = .default
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any?

    var body: some View {
        SettingsGrid {
            SettingsRow("Global Hotkey") {
                Toggle("", isOn: $globalHotkeyEnabled)
                    .labelsHidden()
                    .help("Enable a system-wide keyboard shortcut to toggle recording.")
                    .onChange(of: globalHotkeyEnabled) { _, _ in
                        GlobalHotkeyService.shared.register()
                    }
            }

            if globalHotkeyEnabled {
                SettingsRow("Shortcut") {
                    HStack(spacing: DS.Spacing.sm) {
                        Button {
                            if isRecordingHotkey {
                                stopRecordingHotkey()
                            } else {
                                startRecordingHotkey()
                            }
                        } label: {
                            if isRecordingHotkey {
                                Text("Press shortcut…")
                                    .foregroundStyle(.orange)
                                    .font(DS.Typography.caption)
                            } else {
                                Text(HotkeyDisplayHelper.displayString(
                                    keyCode: UInt16(hotkeyKeyCode),
                                    modifiers: UInt(hotkeyModifiers)
                                ))
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xxs)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Recording hotkey: \(HotkeyDisplayHelper.displayString(keyCode: UInt16(hotkeyKeyCode), modifiers: UInt(hotkeyModifiers)))")

                        Button("Reset") {
                            hotkeyKeyCode = Int(GlobalHotkeyService.defaultKeyCode)
                            hotkeyModifiers = Int(GlobalHotkeyService.defaultModifiers)
                            GlobalHotkeyService.shared.register()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(DS.Typography.caption)
                    }
                }
            }

            Divider()

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
                        Text(TimeInterval(timeout).compactDuration)
                            .monospacedDigit()
                    }
                    .disabled(!config.vadEnabled)
                }
            }

            SettingsRow("Skip Trash on Delete") {
                Toggle("", isOn: $skipTrash)
                    .labelsHidden()
                    .help("When enabled, deleted sessions are permanently removed instead of moving to Trash.")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: globalHotkeyEnabled)
        .animation(.easeInOut(duration: 0.2), value: config.silenceTimeoutSeconds != nil)
        .onAppear { loadConfig() }
        .onDisappear { stopRecordingHotkey() }
        .onChange(of: config) { _, newValue in saveConfig(newValue) }
        .settingsFooter("Changes take effect on next recording.", icon: "arrow.clockwise")
    }

    private func startRecordingHotkey() {
        isRecordingHotkey = true
        // Temporarily unregister the global hotkey so it doesn't fire while recording a new one
        GlobalHotkeyService.shared.unregister()
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier key
            guard !mods.isEmpty else { return event }
            hotkeyKeyCode = Int(event.keyCode)
            hotkeyModifiers = Int(mods.rawValue)
            stopRecordingHotkey()
            GlobalHotkeyService.shared.register()
            return nil // Consume the event
        }
    }

    private func stopRecordingHotkey() {
        isRecordingHotkey = false
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
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
