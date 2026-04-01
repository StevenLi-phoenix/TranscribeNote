import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage("appLanguageOverride") private var appLanguageOverride: String = ""
    @State private var showRestartPrompt = false

    private static let languages: [(label: String, value: String)] = [
        ("System Default", ""),
        ("English", "en"),
        ("简体中文", "zh-Hans"),
        ("繁體中文", "zh-Hant"),
        ("日本語", "ja"),
        ("한국어", "ko"),
        ("Español", "es"),
        ("Français", "fr"),
        ("Deutsch", "de"),
        ("Português", "pt"),
        ("Русский", "ru"),
        ("Italiano", "it"),
        ("العربية", "ar"),
        ("हिन्दी", "hi"),
        ("Türkçe", "tr"),
        ("Tiếng Việt", "vi"),
        ("ไทย", "th"),
        ("Bahasa Indonesia", "id"),
        ("Polski", "pl"),
        ("Nederlands", "nl"),
        ("Svenska", "sv"),
    ]

    /// Resolve a localized string in the target language (not the current app language).
    private func localizedInTarget(_ key: String.LocalizationValue) -> String {
        let code = appLanguageOverride.isEmpty ? Locale.current.language.languageCode?.identifier ?? "en" : appLanguageOverride
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return String(localized: key, bundle: bundle)
        }
        return String(localized: key)
    }

    var body: some View {
        SettingsGrid {
            SettingsRow("Language") {
                Picker("", selection: $appLanguageOverride) {
                    ForEach(Self.languages, id: \.value) { lang in
                        Text(lang.label).tag(lang.value)
                    }
                }
                .labelsHidden()
                .onChange(of: appLanguageOverride) { _, _ in
                    showRestartPrompt = true
                }
            }

            if showRestartPrompt {
                SettingsRow("") {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.orange)
                        Text(localizedInTarget("Restart required to apply language change"))
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                        Button(localizedInTarget("Restart Now")) {
                            TranscribeNoteApp.relaunch()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}
