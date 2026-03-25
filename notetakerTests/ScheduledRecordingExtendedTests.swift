import Testing
import Foundation
@testable import notetaker

@Suite("ScheduledRecording Extended Tests", .serialized)
struct ScheduledRecordingExtendedTests {

    // MARK: - nextFireTime

    @Test func nextFireTimeOnceInFuture() {
        let future = Date().addingTimeInterval(3600)
        let recording = ScheduledRecording(title: "Future", startTime: future, repeatRule: .once)
        #expect(recording.nextFireTime != nil)
        #expect(recording.nextFireTime == future)
    }

    @Test func nextFireTimeOnceInPast() {
        let past = Date().addingTimeInterval(-3600)
        let recording = ScheduledRecording(title: "Past", startTime: past, repeatRule: .once)
        #expect(recording.nextFireTime == nil)
    }

    @Test func nextFireTimeDailyAdvancesPastNow() {
        let yesterday = Date().addingTimeInterval(-86400)
        let recording = ScheduledRecording(title: "Daily", startTime: yesterday, repeatRule: .daily)
        let next = recording.nextFireTime
        #expect(next != nil)
        #expect(next! > Date())
    }

    @Test func nextFireTimeWeeklyAdvancesPastNow() {
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 86400)
        let recording = ScheduledRecording(title: "Weekly", startTime: twoWeeksAgo, repeatRule: .weekly)
        let next = recording.nextFireTime
        #expect(next != nil)
        #expect(next! > Date())
    }

    @Test func nextFireTimeWeekdaysSkipsWeekend() {
        // Use a known Saturday
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        components.hour = 10
        components.minute = 0
        // Find next Saturday
        var testDate = Calendar.current.date(from: components)!
        while Calendar.current.component(.weekday, from: testDate) != 7 { // Saturday = 7
            testDate = Calendar.current.date(byAdding: .day, value: -1, to: testDate)!
        }
        // Set start time to a past Saturday
        let pastSaturday = testDate.addingTimeInterval(-7 * 86400)
        let recording = ScheduledRecording(title: "Weekdays", startTime: pastSaturday, repeatRule: .weekdays)
        let next = recording.nextFireTime
        #expect(next != nil)
        if let next {
            let weekday = Calendar.current.component(.weekday, from: next)
            // Should be Mon-Fri (2-6)
            #expect(weekday >= 2 && weekday <= 6)
        }
    }

    @Test func nextFireTimeDisabledReturnsFireTime() {
        // isEnabled doesn't affect nextFireTime computation itself
        let future = Date().addingTimeInterval(3600)
        let recording = ScheduledRecording(title: "Disabled", startTime: future, repeatRule: .once, isEnabled: false)
        // nextFireTime still calculates, it's schedule() that checks isEnabled
        #expect(recording.nextFireTime != nil)
    }

    // MARK: - Rule computed property

    @Test func ruleComputedProperty() {
        let recording = ScheduledRecording(title: "Test", repeatRule: .daily)
        #expect(recording.rule == .daily)
        #expect(recording.repeatRule == "daily")
    }

    @Test func ruleDefaultsToOnce() {
        let recording = ScheduledRecording(title: "Default")
        #expect(recording.rule == .once)
    }

    @Test func ruleInvalidStringDefaultsToOnce() {
        let recording = ScheduledRecording(title: "Test")
        recording.repeatRule = "invalidValue"
        #expect(recording.rule == .once)
    }

    // MARK: - Init

    @Test func initWithAllParams() {
        let id = UUID()
        let start = Date()
        let schedID = "cal-event-123"
        let recording = ScheduledRecording(
            id: id,
            title: "Meeting",
            label: "Work",
            startTime: start,
            durationMinutes: 60,
            repeatRule: .weekly,
            reminderMinutes: 5,
            isEnabled: true,
            lastTriggeredAt: nil,
            calendarEventIdentifier: schedID
        )
        #expect(recording.id == id)
        #expect(recording.title == "Meeting")
        #expect(recording.label == "Work")
        #expect(recording.startTime == start)
        #expect(recording.durationMinutes == 60)
        #expect(recording.rule == .weekly)
        #expect(recording.reminderMinutes == 5)
        #expect(recording.isEnabled == true)
        #expect(recording.lastTriggeredAt == nil)
        #expect(recording.calendarEventIdentifier == schedID)
    }

    @Test func initDefaults() {
        let recording = ScheduledRecording()
        #expect(recording.title == "")
        #expect(recording.label == "")
        #expect(recording.durationMinutes == nil)
        #expect(recording.rule == .once)
        #expect(recording.reminderMinutes == 1)
        #expect(recording.isEnabled == true)
        #expect(recording.lastTriggeredAt == nil)
        #expect(recording.calendarEventIdentifier == nil)
    }
}

// MARK: - RepeatRule Tests

@Suite("RepeatRule Tests")
struct RepeatRuleTests {

    @Test func allCases() {
        #expect(RepeatRule.allCases.count == 4)
    }

    @Test func rawValues() {
        #expect(RepeatRule.once.rawValue == "once")
        #expect(RepeatRule.daily.rawValue == "daily")
        #expect(RepeatRule.weekly.rawValue == "weekly")
        #expect(RepeatRule.weekdays.rawValue == "weekdays")
    }

    @Test func displayNames() {
        #expect(RepeatRule.once.displayName == "Once")
        #expect(RepeatRule.daily.displayName == "Every day")
        #expect(RepeatRule.weekly.displayName == "Every week")
        #expect(RepeatRule.weekdays.displayName == "Weekdays (Mon–Fri)")
    }

    @Test func idMatchesRawValue() {
        for rule in RepeatRule.allCases {
            #expect(rule.id == rule.rawValue)
        }
    }

    @Test func initFromRawValue() {
        #expect(RepeatRule(rawValue: "once") == .once)
        #expect(RepeatRule(rawValue: "daily") == .daily)
        #expect(RepeatRule(rawValue: "weekly") == .weekly)
        #expect(RepeatRule(rawValue: "weekdays") == .weekdays)
        #expect(RepeatRule(rawValue: "invalid") == nil)
    }
}
