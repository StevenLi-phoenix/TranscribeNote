import Testing
import Foundation
import EventKit
@testable import TranscribeNote

@Suite("CalendarService Extended Tests", .serialized)
struct CalendarServiceExtendedTests {

    let service = CalendarService()

    // MARK: - importAsScheduledRecording

    @Test func importEventWithEndDate() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Team Standup"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(1800) // 30 min

        let recording = service.importAsScheduledRecording(event)
        #expect(recording.title == "Team Standup")
        #expect(recording.durationMinutes == 30)
        #expect(recording.rule == .once) // no recurrence
    }

    @Test func importEventNoEndDate() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Open-ended"
        event.startDate = Date()
        // endDate is nil

        let recording = service.importAsScheduledRecording(event)
        #expect(recording.durationMinutes == nil)
    }

    @Test func importEventWithRecurrence() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Daily Standup"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(900) // 15 min
        event.addRecurrenceRule(EKRecurrenceRule(
            recurrenceWith: .daily,
            interval: 1,
            end: nil
        ))

        let recording = service.importAsScheduledRecording(event)
        #expect(recording.rule == .daily)
        #expect(recording.durationMinutes == 15)
    }

    @Test func importEventPreservesStartTime() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let specificDate = Date(timeIntervalSince1970: 1700000000)
        event.title = "Test"
        event.startDate = specificDate
        event.endDate = specificDate.addingTimeInterval(3600)

        let recording = service.importAsScheduledRecording(event)
        #expect(recording.startTime == specificDate)
    }

    @Test func importEventDefaultReminder() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "No Alarm"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(3600)

        let recording = service.importAsScheduledRecording(event)
        #expect(recording.reminderMinutes == 1) // default
    }

    @Test func importEventWithAlarm() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "With Alarm"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(3600)
        event.addAlarm(EKAlarm(relativeOffset: -600)) // 10 min before

        let recording = service.importAsScheduledRecording(event)
        #expect(recording.reminderMinutes == 10)
    }

    // MARK: - mapRecurrenceRule additional cases

    @Test func weeklyWithSubsetOfWeekdays() {
        // Only Mon/Wed/Fri — should map to .weekly, not .weekdays
        let days = [
            EKRecurrenceDayOfWeek(.monday),
            EKRecurrenceDayOfWeek(.wednesday),
            EKRecurrenceDayOfWeek(.friday),
        ]
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: days,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
        #expect(service.mapRecurrenceRule([rule]) == .weekly)
    }

    @Test func weeklyInterval2FallsToOnce() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 2,
            end: nil
        )
        #expect(service.mapRecurrenceRule([rule]) == .once)
    }

    @Test func multipleRulesUsesFirst() {
        let daily = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        let weekly = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        #expect(service.mapRecurrenceRule([daily, weekly]) == .daily)
    }
}
