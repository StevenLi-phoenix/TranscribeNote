import Testing
import Foundation
import EventKit
@testable import TranscribeNote

@Suite("CalendarService", .serialized)
struct CalendarServiceTests {

    let service = CalendarService()

    // MARK: - mapRecurrenceRule

    @Test("nil rules maps to .once")
    func nilRulesToOnce() {
        #expect(service.mapRecurrenceRule(nil) == .once)
    }

    @Test("Empty rules maps to .once")
    func emptyRulesToOnce() {
        #expect(service.mapRecurrenceRule([]) == .once)
    }

    @Test("Daily interval=1 maps to .daily")
    func dailyRule() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .daily,
            interval: 1,
            end: nil
        )
        #expect(service.mapRecurrenceRule([rule]) == .daily)
    }

    @Test("Weekly interval=1 no specific days maps to .weekly")
    func weeklyRule() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            end: nil
        )
        #expect(service.mapRecurrenceRule([rule]) == .weekly)
    }

    @Test("Weekly interval=1 with Mon-Fri maps to .weekdays")
    func weekdaysRule() {
        let weekdays = [
            EKRecurrenceDayOfWeek(.monday),
            EKRecurrenceDayOfWeek(.tuesday),
            EKRecurrenceDayOfWeek(.wednesday),
            EKRecurrenceDayOfWeek(.thursday),
            EKRecurrenceDayOfWeek(.friday),
        ]
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: weekdays,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
        #expect(service.mapRecurrenceRule([rule]) == .weekdays)
    }

    @Test("Daily interval=2 falls to .once (unsupported)")
    func dailyInterval2ToOnce() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .daily,
            interval: 2,
            end: nil
        )
        #expect(service.mapRecurrenceRule([rule]) == .once)
    }

    @Test("Monthly frequency falls to .once")
    func monthlyToOnce() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .monthly,
            interval: 1,
            end: nil
        )
        #expect(service.mapRecurrenceRule([rule]) == .once)
    }

    @Test("Yearly frequency falls to .once")
    func yearlyToOnce() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .yearly,
            interval: 1,
            end: nil
        )
        #expect(service.mapRecurrenceRule([rule]) == .once)
    }
}
