import AVFoundation
import SwiftUI
import os

// MARK: - VAD Test Runner

/// Lightweight mic capture for testing VAD settings — no file I/O, no ASR forwarding.
@Observable
final class VADTestRunner {
    private static let logger = Logger(subsystem: "com.notetaker", category: "VADTest")

    var isRunning = false
    var audioLevel: Float = 0
    var vadDecision: VADDecision = .forward

    private var audioEngine: AVAudioEngine?
    private var vad: SimpleVAD?
    private let writeQueue = DispatchQueue(label: "com.notetaker.vad-test", qos: .userInitiated)

    func start(config: VADConfig) {
        guard !isRunning else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Self.logger.error("No audio input device for VAD test")
            return
        }

        // Create VAD with buffer-count thresholds matching AudioCaptureService pattern
        // ~43 buffers/sec at 1024 samples / 44.1kHz
        let buffersPerSecond = max(1, Int(inputFormat.sampleRate / 1024))
        vad = SimpleVAD(
            silenceThreshold: config.silenceThreshold,
            silenceBuffersForSuppress: buffersPerSecond * 2,
            silenceBuffersForTimeout: nil
        )

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.writeQueue.async {
                guard let channelData = buffer.floatChannelData else { return }
                let frameCount = Int(buffer.frameLength)
                guard frameCount > 0 else { return }

                var sumOfSquares: Float = 0
                let samples = channelData[0]
                for i in 0..<frameCount {
                    let sample = samples[i]
                    sumOfSquares += sample * sample
                }
                let rms = sqrtf(sumOfSquares / Float(frameCount))
                let db = 20 * log10f(max(rms, 1e-10))
                let level = max(0, min(1, (db + 50) / 50))

                let decision = self.vad?.processLevel(level) ?? .forward

                Task { @MainActor in
                    self.audioLevel = level
                    self.vadDecision = decision
                }
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            isRunning = true
            Self.logger.info("VAD test started")
        } catch {
            Self.logger.error("VAD test start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        vad = nil
        isRunning = false
        audioLevel = 0
        vadDecision = .forward
        Self.logger.info("VAD test stopped")
    }
}

// MARK: - LLM Assignment Tab (assign models to roles)

struct LLMAssignmentTab: View {
    @State private var profiles: [LLMModelProfile] = []
    @State private var liveProfileID: UUID?
    @State private var overallProfileID: UUID?
    @State private var titleProfileID: UUID?
    @State private var overallInheritsLive = false
    @State private var titleInheritsLive = true

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsGrid {
            SettingsRow("Live Model") {
                profilePicker(selection: $liveProfileID)
                    .help("Model used for periodic summarization during recording")
            }

            SettingsRow("Overall: Use Live") {
                Toggle("", isOn: $overallInheritsLive)
                    .labelsHidden()
                    .help("Reuse the live model for post-recording summary")
            }

            if !overallInheritsLive {
                SettingsRow("Overall Model") {
                    profilePicker(selection: $overallProfileID)
                        .help("Model used for post-recording overall summary")
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
                        .help("Model used for automatic title generation")
                }
            }

            SettingsRow("Model Configs") {
                HStack(spacing: DS.Spacing.sm) {
                    let available = profiles.filter {
                        !$0.config.provider.requiresAPIKey || !$0.config.apiKey.isEmpty
                    }.count
                    Text("\(available) / \(profiles.count)")
                        .foregroundStyle(.secondary)
                    Button("Config") {
                        openWindow(id: "models")
                    }
                }
            }
        }
        .onAppear { loadAssignments() }
        .onReceive(NotificationCenter.default.publisher(for: .llmConfigDidSave)) { _ in
            profiles = LLMProfileStore.loadProfiles()
        }
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
            ForEach(profiles) { profile in
                Text("\(profile.name) (\(profile.config.model))")
                    .tag(profile.id as UUID?)
            }
        }
        .labelsHidden()
    }

    private func loadAssignments() {
        profiles = LLMProfileStore.loadProfiles()
        liveProfileID = LLMProfileStore.assignedProfileID(for: .live) ?? profiles.first?.id
        overallProfileID = LLMProfileStore.assignedProfileID(for: .overall) ?? profiles.first?.id
        titleProfileID = LLMProfileStore.assignedProfileID(for: .title) ?? profiles.first?.id
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

    private static let intervalOptions = [1, 2, 3, 5, 10, 15, 30]
    private static let minLengthOptions = [50, 100, 150, 200, 300, 500]
    private static let contextSizeOptions: [(label: String, value: Int)] = [
        ("Small (2K)", 2000),
        ("Medium (4K)", 4000),
        ("Large (8K)", 8000),
        ("Extra Large (16K)", 16000),
    ]

    var body: some View {
        SettingsGrid {
            SettingsRow("Live Summarization") {
                Toggle("", isOn: $config.liveSummarizationEnabled)
                    .labelsHidden()
                    .help("Periodically summarize transcript during recording.")
            }

            SettingsRow("Summary Interval") {
                Picker("", selection: $config.intervalMinutes) {
                    ForEach(Self.intervalOptions, id: \.self) { mins in
                        Text("\(mins) min").tag(mins)
                    }
                }
                .labelsHidden()
                .disabled(!config.liveSummarizationEnabled)
                .help("How often to generate a summary chunk during recording.")
            }

            SettingsRow("Min Transcript Length") {
                Picker("", selection: $config.minTranscriptLength) {
                    ForEach(Self.minLengthOptions, id: \.self) { len in
                        Text("\(len) chars").tag(len)
                    }
                }
                .labelsHidden()
                .help("Minimum transcript characters required before triggering a summary.")
            }

            SettingsRow("Summary Style") {
                Picker("", selection: $config.summaryStyle) {
                    Text("Bullet Points").tag(SummaryStyle.bullets)
                    Text("Paragraph").tag(SummaryStyle.paragraph)
                    Text("Action Items").tag(SummaryStyle.actionItems)
                    Text("Lecture Notes").tag(SummaryStyle.lectureNotes)
                }
                .labelsHidden()
                .help("Output format for generated summaries.")
            }

            SettingsRow("Overall Summary Mode") {
                Picker("", selection: $config.overallSummaryMode) {
                    Text("Auto (chunks if available)").tag(OverallSummaryMode.auto)
                    Text("Raw Text (full transcript)").tag(OverallSummaryMode.rawText)
                    Text("Chunk Summaries Only").tag(OverallSummaryMode.chunkSummaries)
                }
                .labelsHidden()
                .help("How the overall summary is built: from raw transcript, existing chunks, or auto-detect.")
            }

            SettingsRow("Language") {
                Picker("", selection: $pickerSelection) {
                    ForEach(Self.languageOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                .help("Language for summary output. Auto matches the transcript language.")
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
                        .help("Enter a language name, e.g. \"Portuguese\" or \"العربية\".")
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
                    .help("Include previous chunk summaries as context for the next summary.")
            }

            if config.includeContext {
                SettingsRow("Context Size") {
                    Picker("", selection: $config.maxContextTokens) {
                        ForEach(Self.contextSizeOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .help("Max tokens of previous context to include in the prompt.")
                }
            }
        }
        .onAppear { loadConfig() }
        .onChange(of: config) { _, newValue in saveConfig(newValue) }
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
        NotificationCenter.default.post(name: .summarizerConfigDidSave, object: nil)
    }
}

// MARK: - Recording Settings Tab

struct RecordingSettingsTab: View {
    @AppStorage("vadConfigJSON") private var vadConfigJSON: String = ""
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled: Bool = true
    @State private var config: VADConfig = .default
    @State private var vadTest = VADTestRunner()

    private static let timeoutOptions: [(label: String, value: Int)] = [
        ("30s", 30), ("1 min", 60), ("2 min", 120), ("5 min", 300), ("10 min", 600),
    ]

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
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(config.silenceThreshold) },
                            set: { config.silenceThreshold = Float($0) }
                        ),
                        in: 0.01...0.30,
                        step: 0.01
                    )
                    Text(String(format: "%.2f", config.silenceThreshold))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                .disabled(!config.vadEnabled)
                .help("Audio level below this value is treated as silence. Lower = more sensitive.")
            }

            // VAD Test
            SettingsRow("Test VAD") {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Button {
                        if vadTest.isRunning {
                            vadTest.stop()
                        } else {
                            vadTest.start(config: config)
                        }
                    } label: {
                        Label(
                            vadTest.isRunning ? "Stop Test" : "Test Microphone",
                            systemImage: vadTest.isRunning ? "stop.fill" : "mic.fill"
                        )
                    }
                    .disabled(!config.vadEnabled)
                    .help("Test VAD with your microphone to verify threshold settings.")

                    if vadTest.isRunning {
                        VADTestView(
                            level: vadTest.audioLevel,
                            threshold: config.silenceThreshold,
                            decision: vadTest.vadDecision
                        )
                    }
                }
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

            if config.silenceTimeoutSeconds != nil {
                SettingsRow("Silence Timeout") {
                    Picker("", selection: Binding(
                        get: { config.silenceTimeoutSeconds ?? 300 },
                        set: { config.silenceTimeoutSeconds = $0 }
                    )) {
                        ForEach(Self.timeoutOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .disabled(!config.vadEnabled)
                    .help("How long silence must last before auto-stopping the recording.")
                }
            }
        }
        .onAppear { loadConfig() }
        .onChange(of: config) { _, newValue in
            saveConfig(newValue)
            // Restart test with new config if running
            if vadTest.isRunning {
                vadTest.stop()
                vadTest.start(config: newValue)
            }
        }
        .onDisappear { vadTest.stop() }
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

// MARK: - VAD Test Visualization

struct VADTestView: View {
    let level: Float
    let threshold: Float
    let decision: VADDecision

    private var isSpeech: Bool { decision == .forward && level > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // Audio level bar with threshold marker
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: DS.Radius.xs)
                        .fill(.quaternary)

                    // Level fill — green for speech, gray for silence
                    RoundedRectangle(cornerRadius: DS.Radius.xs)
                        .fill(isSpeech ? DS.Colors.audioLevel : Color.secondary.opacity(0.4))
                        .frame(width: geometry.size.width * CGFloat(max(0, min(1, level))))

                    // Threshold marker line
                    Rectangle()
                        .fill(DS.Colors.error.opacity(0.8))
                        .frame(width: 2)
                        .offset(x: geometry.size.width * CGFloat(min(1, threshold)) - 1)
                }
            }
            .frame(height: DS.Spacing.sm)
            .animation(.linear(duration: 0.05), value: level)
            .accessibilityLabel("Microphone level")
            .accessibilityValue("\(Int(level * 100)) percent, \(isSpeech ? "speech detected" : "silence")")

            // Status label
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(isSpeech ? DS.Colors.success : Color.secondary)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(isSpeech ? "Speech" : "Silence")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("|\u{200B} threshold")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.error.opacity(0.8))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 200)
    }
}
