import SwiftUI

struct AboutTab: View {
    @State private var showCopiedVersion = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            // App icon + name + version
            HStack(spacing: DS.Spacing.lg) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Notetaker")
                        .font(DS.Typography.title)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("Notetaker \(appVersion) (\(buildNumber))", forType: .string)
                        showCopiedVersion = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            showCopiedVersion = false
                        }
                    } label: {
                        Text(showCopiedVersion ? "Copied!" : "Version \(appVersion) (\(buildNumber))")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Click to copy version info")
                }
            }

            Divider()
                .frame(maxWidth: 300)

            // Links
            VStack(spacing: DS.Spacing.sm) {
                Link("Report a Bug",
                     destination: URL(string: "https://github.com/StevenLi-phoenix/notetaker/issues/new")!)
                Link("Privacy Policy",
                     destination: PrivacyDisclosureView.privacyPolicyURL)
            }
            .font(DS.Typography.body)

            Spacer()

            // Copyright
            Text("\u{00A9} 2026 Steven Li. All rights reserved.")
                .font(DS.Typography.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, DS.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
    }
}
