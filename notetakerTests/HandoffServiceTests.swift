import Testing
import Foundation
@testable import notetaker

@Suite("HandoffService")
struct HandoffServiceTests {
    @Test func activityTypeConstants() {
        #expect(HandoffService.viewSessionActivityType == "com.notetaker.viewSession")
        #expect(HandoffService.activeRecordingActivityType == "com.notetaker.activeRecording")
    }

    @MainActor @Test func makeViewSessionActivitySetsProperties() {
        let id = UUID()
        let activity = HandoffService.makeViewSessionActivity(
            sessionID: id,
            title: "Team Standup",
            summaryExcerpt: "Discussed sprint progress"
        )
        #expect(activity.activityType == HandoffService.viewSessionActivityType)
        #expect(activity.title == "Team Standup")
        #expect(activity.isEligibleForHandoff == true)
        #expect(activity.isEligibleForSearch == true)
        #expect(activity.userInfo?["sessionID"] as? String == id.uuidString)
    }

    @MainActor @Test func makeViewSessionActivityWithEmptyTitle() {
        let id = UUID()
        let activity = HandoffService.makeViewSessionActivity(
            sessionID: id,
            title: "",
            summaryExcerpt: nil
        )
        #expect(activity.title == "Untitled Recording")
    }

    @MainActor @Test func makeActiveRecordingActivity() {
        let activity = HandoffService.makeActiveRecordingActivity(title: "Sprint Planning")
        #expect(activity.activityType == HandoffService.activeRecordingActivityType)
        #expect(activity.title == "Recording: Sprint Planning")
        #expect(activity.isEligibleForHandoff == true)
        #expect(activity.isEligibleForSearch == false)
    }

    @MainActor @Test func makeActiveRecordingActivityEmptyTitle() {
        let activity = HandoffService.makeActiveRecordingActivity(title: "")
        #expect(activity.title == "Recording: Untitled")
    }

    @MainActor @Test func sessionIDFromValidActivity() {
        let id = UUID()
        let activity = NSUserActivity(activityType: HandoffService.viewSessionActivityType)
        activity.userInfo = ["sessionID": id.uuidString]

        let parsed = HandoffService.sessionID(from: activity)
        #expect(parsed == id)
    }

    @MainActor @Test func sessionIDFromWrongActivityType() {
        let activity = NSUserActivity(activityType: "com.other.type")
        activity.userInfo = ["sessionID": UUID().uuidString]

        let parsed = HandoffService.sessionID(from: activity)
        #expect(parsed == nil)
    }

    @MainActor @Test func sessionIDFromMissingUserInfo() {
        let activity = NSUserActivity(activityType: HandoffService.viewSessionActivityType)
        activity.userInfo = nil

        let parsed = HandoffService.sessionID(from: activity)
        #expect(parsed == nil)
    }

    @MainActor @Test func sessionIDFromInvalidUUID() {
        let activity = NSUserActivity(activityType: HandoffService.viewSessionActivityType)
        activity.userInfo = ["sessionID": "not-a-uuid"]

        let parsed = HandoffService.sessionID(from: activity)
        #expect(parsed == nil)
    }

    @MainActor @Test func sessionIDFromMissingKey() {
        let activity = NSUserActivity(activityType: HandoffService.viewSessionActivityType)
        activity.userInfo = ["otherKey": "value"]

        let parsed = HandoffService.sessionID(from: activity)
        #expect(parsed == nil)
    }

    @MainActor @Test func summaryExcerptTruncation() {
        let longExcerpt = String(repeating: "A", count: 1000)
        let activity = HandoffService.makeViewSessionActivity(
            sessionID: UUID(),
            title: "Test",
            summaryExcerpt: longExcerpt
        )
        // Activity should be created without error even with long excerpt
        #expect(activity.title == "Test")
    }
}
