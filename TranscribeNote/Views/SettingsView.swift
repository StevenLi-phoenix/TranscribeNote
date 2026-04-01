import SwiftUI

struct SettingsView: View {
    @AppStorage("hasShownPrivacyDisclosure") private var hasShownDisclosure = false
    @State private var showPrivacySheet = false

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            LLMAssignmentTab()
                .tabItem { Label("LLM", systemImage: "brain") }

            SummarizationSettingsTab()
                .tabItem { Label("Summarization", systemImage: "text.badge.star") }

            RecordingSettingsTab()
                .tabItem { Label("Recording", systemImage: "mic") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 560)
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
