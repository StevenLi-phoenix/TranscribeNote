import SwiftUI
import os

struct MeetingRecapSheet: View {
    let recapData: MeetingRecapFormatter.RecapData
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedFeedback = false
    @State private var recipientEmail = ""

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "MeetingRecapSheet")

    private var subject: String {
        MeetingRecapFormatter.formatSubject(title: recapData.title, date: recapData.date)
    }

    private var bodyText: String {
        MeetingRecapFormatter.formatBody(from: recapData)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // Subject preview
                HStack {
                    Text("Subject:")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text(subject)
                        .font(DS.Typography.body)
                        .fontWeight(.medium)
                }

                // Optional recipient field
                TextField("Recipients (optional)", text: $recipientEmail)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typography.callout)

                // Body preview
                ScrollView {
                    Text(bodyText)
                        .font(DS.Typography.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                // Actions
                HStack {
                    Spacer()

                    Button {
                        copyToClipboard()
                    } label: {
                        Label(showCopiedFeedback ? "Copied!" : "Copy", systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openInMail()
                    } label: {
                        Label("Open in Mail", systemImage: "envelope")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Meeting Recap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bodyText, forType: .string)
        Self.logger.debug("Copied meeting recap to clipboard")
        withAnimation { showCopiedFeedback = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopiedFeedback = false }
        }
    }

    private func openInMail() {
        let recipients = recipientEmail.isEmpty ? [] : recipientEmail.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let url = MeetingRecapFormatter.mailtoURL(to: recipients, subject: subject, body: bodyText) {
            NSWorkspace.shared.open(url)
            Self.logger.info("Opened mail client with recap")
        }
    }
}
