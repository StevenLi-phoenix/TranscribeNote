import AppIntents
import SwiftData

struct SessionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recording Session")
    static var defaultQuery = SessionEntityQuery()

    var id: String  // UUID string from RecordingSession
    var title: String
    var date: Date
    var segmentCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(date.formatted(date: .abbreviated, time: .shortened))"
        )
    }
}

struct SessionEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        try await MainActor.run {
            try AppIntentState.shared.ensureReady()
            guard let container = AppIntentState.shared.modelContainerRef else { return [] }
            let context = ModelContext(container)
            var results: [SessionEntity] = []
            for idStr in identifiers {
                guard let uuid = UUID(uuidString: idStr) else { continue }
                let predicate = #Predicate<RecordingSession> { $0.id == uuid }
                var descriptor = FetchDescriptor(predicate: predicate)
                descriptor.fetchLimit = 1
                if let session = try context.fetch(descriptor).first {
                    results.append(SessionEntity(
                        id: session.id.uuidString,
                        title: session.title,
                        date: session.startedAt,
                        segmentCount: session.segments.count
                    ))
                }
            }
            return results
        }
    }

    func suggestedEntities() async throws -> [SessionEntity] {
        try await MainActor.run {
            try AppIntentState.shared.ensureReady()
            guard let container = AppIntentState.shared.modelContainerRef else { return [] }
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<RecordingSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 10
            let sessions = try context.fetch(descriptor)
            return sessions.map { session in
                SessionEntity(
                    id: session.id.uuidString,
                    title: session.title,
                    date: session.startedAt,
                    segmentCount: session.segments.count
                )
            }
        }
    }
}
