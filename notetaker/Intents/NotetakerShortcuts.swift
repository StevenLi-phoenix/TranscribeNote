import AppIntents

struct NotetakerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording with \(.applicationName)",
                "Begin meeting recording in \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "record.circle"
        )

        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop recording with \(.applicationName)",
                "End meeting recording in \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.circle"
        )

        AppShortcut(
            intent: GetLastSummaryIntent(),
            phrases: [
                "Get meeting summary from \(.applicationName)",
                "Summarize last meeting with \(.applicationName)"
            ],
            shortTitle: "Get Summary",
            systemImageName: "doc.text"
        )

        AppShortcut(
            intent: SearchTranscriptsIntent(),
            phrases: [
                "Search transcripts in \(.applicationName)",
                "Find in recordings with \(.applicationName)"
            ],
            shortTitle: "Search Transcripts",
            systemImageName: "magnifyingglass"
        )
    }
}
