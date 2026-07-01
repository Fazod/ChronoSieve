import Foundation

enum MockCalendarFixtures {
    static let workCalendar = CalendarSource(id: "mock-work", title: "Calendar", colorHex: "#3B82F6")
    static let personalCalendar = CalendarSource(id: "mock-personal", title: "Personal", colorHex: "#22C55E")
    static let birthdaysCalendar = CalendarSource(id: "mock-birthdays", title: "Birthdays", colorHex: "#8B5CF6")
    static let travelCalendar = CalendarSource(id: "mock-travel", title: "Travel", colorHex: "#F97316")

    static func calendars() -> [CalendarSource] {
        [workCalendar, personalCalendar, birthdaysCalendar, travelCalendar]
    }

    static func events(referenceDate: Date = Date()) -> [CalendarEvent] {
        let calendar = Calendar.autoupdatingCurrent
        let baseDay = calendar.startOfDay(for: referenceDate)

        func timed(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: baseDay) ?? baseDay
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        func allDayRange(_ dayOffset: Int, spanDays: Int = 1) -> DateInterval {
            let start = calendar.date(byAdding: .day, value: dayOffset, to: baseDay) ?? baseDay
            let end = calendar.date(byAdding: .day, value: spanDays, to: start) ?? start.addingTimeInterval(TimeInterval(spanDays * 86_400))
            return DateInterval(start: start, end: end)
        }

        let birthday = allDayRange(0)
        let teamOffsite = allDayRange(3, spanDays: 2)

        return [
            CalendarEvent(
                id: "mock-birthday-1",
                title: "Jürgen Schicklgruber's 32nd Birthday",
                startDate: birthday.start,
                endDate: birthday.end,
                isAllDay: true,
                notes: "Buy cake and send greeting 🎉",
                location: nil,
                calendarTitle: birthdaysCalendar.title,
                calendarColorHex: birthdaysCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-standup",
                title: "GES: Standup",
                startDate: timed(0, 9, 45),
                endDate: timed(0, 10, 0),
                isAllDay: false,
                notes: "Daily sync\nTeams: https://teams.microsoft.com/l/meetup-join/19%3ameeting_mock_standup",
                location: "Microsoft Teams",
                calendarTitle: workCalendar.title,
                calendarColorHex: workCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-breakouts",
                title: "GES: Breakouts",
                startDate: timed(0, 10, 0),
                endDate: timed(0, 10, 15),
                isAllDay: false,
                notes: "Split into pairs and capture action items.",
                location: "Microsoft Teams",
                calendarTitle: workCalendar.title,
                calendarColorHex: workCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-media-standup",
                title: "Servus Media-Standup",
                startDate: timed(0, 10, 30),
                endDate: timed(0, 11, 0),
                isAllDay: false,
                notes: "Agenda in Confluence: https://example.atlassian.net/wiki/spaces/CS/pages/standup",
                location: "Microsoft Teams",
                calendarTitle: workCalendar.title,
                calendarColorHex: workCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-rehearsal",
                title: "Reha",
                startDate: timed(0, 11, 30),
                endDate: timed(0, 15, 30),
                isAllDay: false,
                notes: "Bring referral documents and water bottle.",
                location: "BBRZ, Vienna",
                calendarTitle: personalCalendar.title,
                calendarColorHex: personalCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-lunch",
                title: "Lunch with Alex",
                startDate: timed(0, 12, 15),
                endDate: timed(0, 13, 0),
                isAllDay: false,
                notes: "Try the new ramen place nearby.",
                location: "Neko Ramen",
                calendarTitle: personalCalendar.title,
                calendarColorHex: personalCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-maintenance-window",
                title: "Release Window",
                startDate: timed(0, 23, 0),
                endDate: timed(1, 1, 0),
                isAllDay: false,
                notes: "Observe production rollout and verify metrics.",
                location: "Remote",
                calendarTitle: workCalendar.title,
                calendarColorHex: workCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-design-review",
                title: "ChronoSieve UI Design Review",
                startDate: timed(1, 14, 0),
                endDate: timed(1, 15, 0),
                isAllDay: false,
                notes: "Review grouped glass cards\nFigma: https://figma.com/file/mock-liquid-glass",
                location: "Meeting Room 4B",
                calendarTitle: workCalendar.title,
                calendarColorHex: workCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-dentist",
                title: "Dentist",
                startDate: timed(1, 17, 30),
                endDate: timed(1, 18, 30),
                isAllDay: false,
                notes: "Bring insurance card.",
                location: "Mariahilfer Straße 88",
                calendarTitle: personalCalendar.title,
                calendarColorHex: personalCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-focus",
                title: "Focus Block",
                startDate: timed(2, 8, 30),
                endDate: timed(2, 10, 30),
                isAllDay: false,
                notes: "No meetings. Deep work.",
                location: "Home Office",
                calendarTitle: personalCalendar.title,
                calendarColorHex: personalCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-offsite",
                title: "Product Offsite",
                startDate: teamOffsite.start,
                endDate: teamOffsite.end,
                isAllDay: true,
                notes: "Two-day team offsite with roadmap planning.",
                location: "Semmering",
                calendarTitle: workCalendar.title,
                calendarColorHex: workCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-flight",
                title: "Flight to Berlin",
                startDate: timed(5, 6, 20),
                endDate: timed(5, 8, 0),
                isAllDay: false,
                notes: "Check in online 24h before departure.",
                location: "VIE → BER",
                calendarTitle: travelCalendar.title,
                calendarColorHex: travelCalendar.colorHex
            ),
            CalendarEvent(
                id: "mock-family-dinner",
                title: "Family Dinner",
                startDate: timed(6, 19, 0),
                endDate: timed(6, 21, 30),
                isAllDay: false,
                notes: "Bring dessert.",
                location: "Parents' House",
                calendarTitle: personalCalendar.title,
                calendarColorHex: personalCalendar.colorHex
            )
        ]
        .sorted(by: { $0.startDate < $1.startDate })
    }
}
