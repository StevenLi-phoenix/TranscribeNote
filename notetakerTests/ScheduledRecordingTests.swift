import Testing
import Foundation
@testable import notetaker

@Suite("ScheduledRecording", .serialized)
struct ScheduledRecordingTests {

    // MARK: - nextFireTime

    @Test("Once: future startTime returns that time")
    func onceNextFireTimeFuture() {
        let future = Date().addingTimeInterval(3600)
        let recording = ScheduledRecording(startTime: future, repeatRule: .once)
        #expect(recording.nextFireTime != nil)
        #expect(recording.nextFireTime == future)
    }

    @Test("Once: past startTime returns nil")
    func onceNextFireTimePast() {
        let past = Date().addingTimeInterval(-3600)
        let recording = ScheduledRecording(startTime: past, repeatRule: .once)
        #expect(recording.nextFireTime == nil)
    }

    @Test("Daily: past startTime advances to future")
    func dailyNextFireTime() {
        let yesterday = Date().addingTimeInterval(-86400)
        let recording = ScheduledRecording(startTime: yesterday, repeatRule: .daily)
        let next = recording.nextFireTime
        #expect(next != nil)
        #expect(next! > Date())
    }

    @Test("Weekly: past startTime advances by weeks")
    func weeklyNextFireTime() {
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 86400)
        let recording = ScheduledRecording(startTime: twoWeeksAgo, repeatRule: .weekly)
        let next = recording.nextFireTime
        #expect(next != nil)
        #expect(next! > Date())
    }

    @Test("Weekdays: skips weekends")
    func weekdaysNextFireTime() {
        // Use a known Saturday
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 21 // Saturday
        components.hour = 10
        let saturday = Calendar.current.date(from: components)!

        let recording = ScheduledRecording(startTime: saturday.addingTimeInterval(-604800), repeatRule: .weekdays)
        // The next fire time should skip Saturday and Sunday
        if let next = recording.nextFireTime {
            let weekday = Calendar.current.component(.weekday, from: next)
            // Weekday should be Mon(2) - Fri(6)
            #expect(weekday >= 2 && weekday <= 6)
        }
    }

    // MARK: - RepeatRule

    @Test("RepeatRule.weekly has correct display name")
    func weeklyDisplayName() {
        #expect(RepeatRule.weekly.displayName == "Every week")
    }

    @Test("RepeatRule.allCases includes weekly")
    func allCasesIncludesWeekly() {
        #expect(RepeatRule.allCases.contains(.weekly))
    }

    // MARK: - calendarEventIdentifier

    @Test("calendarEventIdentifier defaults to nil")
    func calendarEventIdentifierDefault() {
        let recording = ScheduledRecording(title: "Test")
        #expect(recording.calendarEventIdentifier == nil)
    }

    @Test("calendarEventIdentifier can be set")
    func calendarEventIdentifierSet() {
        let recording = ScheduledRecording(title: "Test", calendarEventIdentifier: "EK123")
        #expect(recording.calendarEventIdentifier == "EK123")
    }
}
