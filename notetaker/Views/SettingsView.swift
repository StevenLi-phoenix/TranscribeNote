import SwiftUI

struct SettingsView: View {
    @AppStorage("hasShownPrivacyDisclosure") private var hasShownDisclosure = false
    @State private var showPrivacySheet = false

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

            DiagnosticsTab()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 520)
        .onAppear {
            if !hasShownDisclosure {
                showPrivacySheet = true
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyDisclosureView {
                hasShownDisclosure = true
                showPrivacySheet = false
            }
        }
    }
}
