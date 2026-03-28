import Foundation
import CoreSpotlight
import os

/// Manages NSUserActivity for Handoff and Spotlight search integration.
nonisolated enum HandoffService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "HandoffService")

    // MARK: - Activity Types

    /// Activity type for viewing a recording session
    static let viewSessionActivityType = "com.notetaker.viewSession"

    /// Activity type for active recording
    static let activeRecordingActivityType = "com.notetaker.activeRecording"

    // MARK: - Activity Creation

    /// Create an NSUserActivity for viewing a specific session.
    /// Eligible for Handoff (cross-device) and Spotlight search.
    static func makeViewSessionActivity(
        sessionID: UUID,
        title: String,
        summaryExcerpt: String?
    ) -> NSUserActivity {
        let activity = NSUserActivity(activityType: viewSessionActivityType)
        activity.title = title.isEmpty ? "Untitled Recording" : title
        activity.userInfo = ["sessionID": sessionID.uuidString]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.isEligibleForPublicIndexing = false

        // Content description for Spotlight
        if let excerpt = summaryExcerpt, !excerpt.isEmpty {
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.contentDescription = String(excerpt.prefix(300))
            attrs.title = activity.title
            activity.contentAttributeSet = attrs
        }

        // Required for Handoff to work
        activity.requiredUserInfoKeys = ["sessionID"]

        logger.debug("Created viewSession activity for \(sessionID)")
        return activity
    }

    /// Create an NSUserActivity for an active recording.
    static func makeActiveRecordingActivity(title: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activeRecordingActivityType)
        activity.title = "Recording: \(title.isEmpty ? "Untitled" : title)"
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.requiredUserInfoKeys = []

        logger.debug("Created activeRecording activity")
        return activity
    }

    // MARK: - Parsing

    /// Extract session UUID from an incoming NSUserActivity.
    static func sessionID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == viewSessionActivityType else { return nil }
        guard let idString = activity.userInfo?["sessionID"] as? String else { return nil }
        return UUID(uuidString: idString)
    }
}
