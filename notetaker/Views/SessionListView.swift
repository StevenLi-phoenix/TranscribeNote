import SwiftUI
import SwiftData

struct SessionListView: View {
    @Query(sort: \RecordingSession.startedAt, order: .reverse)
    private var sessions: [RecordingSession]

    @Binding var selectedSessionID: UUID?

    @State private var groupedSessions: [(date: Date, sessions: [RecordingSession])] = []

    private func updateGroupedSessions() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startedAt)
        }
        groupedSessions = grouped.sorted { $0.key > $1.key }
            .map { (date: $0.key, sessions: $0.value) }
    }

    var body: some View {
        List(selection: $selectedSessionID) {
            ForEach(groupedSessions, id: \.date) { group in
                Section(group.date.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(group.sessions, id: \.id) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear { updateGroupedSessions() }
        .onChange(of: sessions) { updateGroupedSessions() }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "tray",
                    description: Text("Start a recording to create your first session")
                )
            }
        }
    }
}

private struct SessionRowView: View {
    let session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if session.totalDuration > 0 {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(session.totalDuration.compactDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = [session.title, session.startedAt.formatted(date: .omitted, time: .shortened)]
        if session.totalDuration > 0 {
            parts.append(session.totalDuration.compactDuration)
        }
        return parts.joined(separator: ", ")
    }
}
