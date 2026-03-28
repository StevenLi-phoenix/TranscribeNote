import SwiftData
import Foundation

/// NotetakerMigrationPlan - Schema versioning and migration plan
///
/// This migration plan establishes versioning infrastructure for the app's
/// SwiftData schema. Currently contains only V1; when V2 is shipped, add
/// migration stages here.
///
/// ## Adding a new schema version (V2, V3, etc.):
///
/// 1. Create new schema file (e.g., SchemaV2.swift):
///    ```swift
///    enum SchemaV2: VersionedSchema {
///        static var versionIdentifier = Schema.Version(2, 0, 0)
///        static var models: [any PersistentModel.Type] {
///            [RecordingSession.self, TranscriptSegment.self, SummaryBlock.self]
///        }
///        // ... modified models with new fields or relationships ...
///    }
///    ```
///
/// 2. Add to schemas list:
///    ```swift
///    static var schemas: [any VersionedSchema.Type] {
///        [SchemaV1.self, SchemaV2.self]  // Add new version
///    }
///    ```
///
/// 3. Add migration stage:
///    ```swift
///    static var stages: [MigrationStage] {
///        [
///            // Lightweight migration for simple changes (new optional/default fields)
///            MigrationStage.lightweight(
///                fromVersion: SchemaV1.self,
///                toVersion: SchemaV2.self
///            ),
///
///            // Custom migration for complex data transformations
///            MigrationStage.custom(
///                fromVersion: SchemaV1.self,
///                toVersion: SchemaV2.self,
///                willMigrate: { context in
///                    // Pre-migration setup
///                },
///                didMigrate: { context in
///                    // Transform existing data to new schema
///                    let sessions = try context.fetch(FetchDescriptor<SchemaV2.RecordingSession>())
///                    for session in sessions {
///                        // Modify data as needed
///                    }
///                    try context.save()
///                }
///            )
///        ]
///    }
///    ```
///
/// ## Testing migrations:
/// - Always test with a copy of production data
/// - Verify existing data loads correctly after migration
/// - Check new fields have correct default values
/// - Ensure relationships are preserved
///
/// References:
/// - https://azamsharp.com/2026/02/14/if-you-are-not-versioning-your-swiftdata-schema.html
/// - https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-a-complex-migration-using-versionedschema
enum NotetakerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            // V3 adds ScheduledRecording — new model, no existing data affected, lightweight is sufficient.
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            // V4 adds audioFilePaths to RecordingSession for multi-clip pause/resume support.
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            // V5 adds isPartial to RecordingSession for force-quit detection.
            .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self),
            // V6 adds calendarEventIdentifier to ScheduledRecording, scheduledRecordingID to RecordingSession.
            .lightweight(fromVersion: SchemaV5.self, toVersion: SchemaV6.self),
            // V7 adds sentiment to TranscriptSegment for emotion/sentiment tagging.
            .lightweight(fromVersion: SchemaV6.self, toVersion: SchemaV7.self),
        ]
    }
}
