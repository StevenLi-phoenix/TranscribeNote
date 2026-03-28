import SwiftUI

struct PrivacyDisclosureView: View {
    static let privacyPolicyURL = URL(string: "https://github.com/StevenLi-phoenix/notetaker/blob/main/docs/PRIVACY_POLICY.md")!

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Privacy Notice")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                disclosureSection(
                    title: "When you configure an external LLM provider, Notetaker will send:",
                    items: [
                        "Transcript text from your recordings",
                        "Optional context from previous summaries"
                    ]
                )

                disclosureSection(
                    title: "Data is sent to:",
                    items: [
                        "The API endpoint you configure (OpenAI, Anthropic, or custom)",
                        "Notetaker does not collect or store your data on any server"
                    ]
                )

                disclosureSection(
                    title: "You control:",
                    items: [
                        "Which provider to use",
                        "Your own API key (stored securely in macOS Keychain)",
                        "When summaries are generated"
                    ]
                )
            }
            .font(.body)
            .padding()
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            Button("I Understand") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Link("View Full Privacy Policy",
                 destination: Self.privacyPolicyURL)
                .font(.caption)
        }
        .padding(DS.Spacing.xxl)
        .frame(width: 480)
    }

    private func disclosureSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .font(.headline)
                .padding(.top, DS.Spacing.xs)

            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "circle.fill")
                    .font(.body)
                    .labelStyle(BulletLabelStyle())
            }
        }
    }
}

/// Compact bullet-point label style using a small circle as the icon.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            configuration.icon
                .font(.system(size: 4))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}
