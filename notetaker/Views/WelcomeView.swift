import SwiftUI
import os

struct WelcomeView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "WelcomeView")

    let onDismiss: () -> Void
    @State private var currentPage = 0

    /// Total page count: 3 info pages + 1 model config page
    private let totalPages = 4

    private let infoPages: [WelcomePage] = [
        WelcomePage(
            icon: "mic.badge.plus",
            iconColor: .blue,
            title: "Welcome to TranscribeNote",
            subtitle: "Your intelligent meeting companion for macOS",
            features: [
                WelcomeFeature(icon: "waveform", text: "Record and transcribe meetings in real-time"),
                WelcomeFeature(icon: "text.badge.star", text: "Get AI-powered summaries and action items"),
                WelcomeFeature(icon: "bubble.left.and.bubble.right", text: "Chat with your transcripts to find key details"),
            ]
        ),
        WelcomePage(
            icon: "record.circle",
            iconColor: .red,
            title: "Start Recording",
            subtitle: "Getting started is simple",
            features: [
                WelcomeFeature(icon: "command", text: "Press \u{2318}N or click + to start a new recording"),
                WelcomeFeature(icon: "pause.fill", text: "Pause and resume anytime without losing progress"),
                WelcomeFeature(icon: "calendar.badge.plus", text: "Schedule recordings or import from Calendar"),
            ]
        ),
        WelcomePage(
            icon: "sparkles",
            iconColor: .purple,
            title: "Powerful Features",
            subtitle: "Discover what TranscribeNote can do",
            features: [
                WelcomeFeature(icon: "command", text: "Press \u{2318}K to open the Command Palette"),
                WelcomeFeature(icon: "arrow.left.arrow.right", text: "Use Space to play/pause, arrow keys to seek"),
                WelcomeFeature(icon: "gear", text: "You can always adjust models in Settings later"),
            ]
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            Group {
                if currentPage < infoPages.count {
                    infoPageContent(infoPages[currentPage])
                } else {
                    WelcomeModelConfigPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            Divider()

            // Navigation bar
            HStack {
                // Page dots
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentPage > 0 {
                    Button("Back") {
                        currentPage -= 1
                    }
                    .buttonStyle(.bordered)
                }

                if currentPage < totalPages - 1 {
                    Button("Next") {
                        currentPage += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") {
                        Self.logger.info("Onboarding completed")
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private func infoPageContent(_ page: WelcomePage) -> some View {
        VStack(spacing: DS.Spacing.xl) {
            Image(systemName: page.icon)
                .font(.system(size: 48))
                .foregroundStyle(page.iconColor)
                .id(page.icon)

            VStack(spacing: DS.Spacing.sm) {
                Text(page.title)
                    .font(DS.Typography.title)
                    .bold()
                Text(page.subtitle)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(page.features) { feature in
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: feature.icon)
                            .frame(width: 24)
                            .foregroundStyle(.secondary)
                        Text(feature.text)
                            .font(DS.Typography.body)
                    }
                }
            }
            .padding(DS.Spacing.lg)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .padding(DS.Spacing.xxl)
    }
}

// MARK: - Model Config Page

/// Quick LLM provider setup shown during onboarding.
/// Saves a default profile so the user can start generating summaries immediately.
private struct WelcomeModelConfigPage: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "WelcomeModelConfig")

    @State private var selectedProvider: LLMProvider = .foundationModels
    @State private var apiKey = ""
    @State private var model = ""
    @State private var baseURL = ""
    @State private var showPrivacyNotice = false
    @AppStorage("hasShownPrivacyDisclosure") private var hasShownPrivacyDisclosure = false

    private let labelWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.teal)

            VStack(spacing: DS.Spacing.sm) {
                Text("Set Up AI Model")
                    .font(DS.Typography.title)
                    .bold()
                Text("Choose a provider for summaries and chat")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Spacing.md, verticalSpacing: DS.Spacing.sm) {
                    GridRow {
                        Text("Provider")
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth, alignment: .trailing)
                        Picker("", selection: $selectedProvider) {
                            ForEach(LLMProvider.availableProviders.filter { provider in
                                provider != .foundationModels || FoundationModelsEngine.isModelAvailable
                            }, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    if selectedProvider == .foundationModels {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "apple.intelligence")
                                .foregroundStyle(.secondary)
                            Text("On-device model. No API key or setup needed.")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .gridCellColumns(2)
                    }

                    if selectedProvider == .ollama {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(.secondary)
                            Text("Requires local Ollama installation.")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .gridCellColumns(2)
                    }

                    if selectedProvider == .custom {
                        GridRow {
                            Text("Base URL")
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                                .frame(width: labelWidth, alignment: .trailing)
                            TextField("http://localhost:1234/v1", text: $baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if selectedProvider.requiresAPIKey {
                        GridRow {
                            Text("API Key")
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                                .frame(width: labelWidth, alignment: .trailing)
                            SecureField("Stored in Keychain", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if selectedProvider != .foundationModels {
                        GridRow {
                            Text("Model")
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                                .frame(width: labelWidth, alignment: .trailing)
                            TextField(selectedProvider.defaultModel, text: $model)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .padding(DS.Spacing.lg)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            Text("You can change this anytime in Settings > Models.")
                .font(DS.Typography.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(DS.Spacing.xxl)
        .onChange(of: selectedProvider) { _, newProvider in
            model = ""
            baseURL = newProvider == .custom ? newProvider.defaultBaseURL : ""
            apiKey = ""

            // Show privacy notice when selecting a provider that sends data externally
            if newProvider != .foundationModels && !hasShownPrivacyDisclosure {
                showPrivacyNotice = true
            }
        }
        .sheet(isPresented: $showPrivacyNotice) {
            PrivacyDisclosureView(onDismiss: {
                hasShownPrivacyDisclosure = true
                showPrivacyNotice = false
            }, onDecline: {
                // User declined — fall back to Apple Intelligence
                showPrivacyNotice = false
                selectedProvider = .foundationModels
                model = ""
                apiKey = ""
                baseURL = ""
            })
        }
        .onDisappear {
            saveQuickConfig()
        }
    }

    /// Persist the chosen provider as the default profile when leaving this page.
    private func saveQuickConfig() {
        let effectiveModel = model.isEmpty ? selectedProvider.defaultModel : model
        let effectiveBaseURL = baseURL.isEmpty ? selectedProvider.defaultBaseURL : baseURL
        let config = LLMConfig(
            provider: selectedProvider,
            model: effectiveModel,
            apiKey: apiKey,
            baseURL: effectiveBaseURL,
            temperature: 0.7,
            maxTokens: selectedProvider.defaultMaxTokens
        )

        // Load existing profiles, update first profile or create one
        var profiles = LLMProfileStore.loadProfiles()
        if profiles.isEmpty {
            profiles.append(LLMModelProfile(name: "\(selectedProvider.displayName) \(effectiveModel)", config: config))
        } else {
            profiles[0].config = config
            profiles[0].name = "\(selectedProvider.displayName) \(effectiveModel)"
        }

        // Save API key to Keychain for the profile
        if !apiKey.isEmpty {
            let keychainKey = "notetaker.profile.\(profiles[0].id.uuidString).apiKey"
            KeychainService.save(key: keychainKey, value: apiKey)
        }

        LLMProfileStore.saveProfiles(profiles)
        Self.logger.info("Saved quick config: provider=\(selectedProvider.rawValue), model=\(effectiveModel)")
    }
}

// MARK: - Models

private struct WelcomePage: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let features: [WelcomeFeature]
}

private struct WelcomeFeature: Identifiable {
    let id = UUID()
    let icon: String
    let text: LocalizedStringKey
}
