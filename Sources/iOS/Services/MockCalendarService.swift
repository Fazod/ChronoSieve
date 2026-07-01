import Foundation

@MainActor
final class MockCalendarService: CalendarServiceProtocol {
    private struct MockSeed {
        let id: String
        let calendarID: String
        let title: String
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        let notes: String?
        let location: String?
        let calendarTitle: String
        let calendarColorHex: String
    }

    private var changeHandler: (() -> Void)?

    func requestAccess() async -> Bool {
        true
    }

    func fetchCalendars() async -> [CalendarSource] {
        [
            CalendarSource(id: "mock-work", title: "Calendar", colorHex: "#3B82F6"),
            CalendarSource(id: "mock-personal", title: "Personal", colorHex: "#22C55E"),
            CalendarSource(id: "mock-birthdays", title: "Birthdays", colorHex: "#8B5CF6")
        ]
    }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) async -> [CalendarEvent] {
        guard !calendarIDs.isEmpty else { return [] }

        return makeMockSeeds()
            .filter { calendarIDs.contains($0.calendarID) }
            .filter { overlaps(seed: $0, interval: interval) }
            .map {
                CalendarEvent(
                    id: $0.id,
                    title: $0.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isAllDay: $0.isAllDay,
                    notes: $0.notes,
                    location: $0.location,
                    calendarTitle: $0.calendarTitle,
                    calendarColorHex: $0.calendarColorHex
                )
            }
            .sorted(by: { $0.startDate < $1.startDate })
    }

    func setChangeHandler(_ handler: @escaping () -> Void) {
        changeHandler = handler
    }

    private func makeMockSeeds() -> [MockSeed] {
        let calendar = Calendar.autoupdatingCurrent
        let baseDay = calendar.startOfDay(for: Date())

        func date(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: baseDay) ?? baseDay
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        return [
            MockSeed(
                id: "mock-birthday-1",
                calendarID: "mock-birthdays",
                title: "Jürgen Schicklgruber's 32nd Birthday",
                startDate: baseDay,
                endDate: calendar.date(byAdding: .day, value: 1, to: baseDay) ?? baseDay.addingTimeInterval(86_400),
                isAllDay: true,
                notes: "Buy cake and send greeting 🎉",
                location: nil,
                calendarTitle: "Birthdays",
                calendarColorHex: "#8B5CF6"
            ),
            MockSeed(
                id: "mock-standup",
                calendarID: "mock-work",
                title: "GES: Standup",
                startDate: date(0, 9, 45),
                endDate: date(0, 10, 0),
                isAllDay: false,
                notes: "Daily sync\nTeams: https://teams.microsoft.com/l/meetup-join/19%3ameeting_mock_standup",
                location: "Microsoft Teams",
                calendarTitle: "Calendar",
                calendarColorHex: "#3B82F6"
            ),
            MockSeed(
                id: "mock-breakouts",
                calendarID: "mock-work",
                title: "GES: Breakouts",
                startDate: date(0, 10, 0),
                endDate: date(0, 10, 15),
                isAllDay: false,
                notes: "Split into pairs and capture action items.",
                location: "Microsoft Teams",
                calendarTitle: "Calendar",
                calendarColorHex: "#3B82F6"
            ),
            MockSeed(
                id: "mock-media-standup",
                calendarID: "mock-work",
                title: "Servus Media-Standup",
                startDate: date(0, 10, 30),
                endDate: date(0, 11, 0),
                isAllDay: false,
                notes: "Agenda in Confluence: https://example.atlassian.net/wiki/spaces/CS/pages/standup",
                location: "Microsoft Teams",
                calendarTitle: "Calendar",
                calendarColorHex: "#3B82F6"
            ),
            MockSeed(
                id: "mock-rehearsal",
                calendarID: "mock-personal",
                title: "Reha",
                startDate: date(0, 11, 30),
                endDate: date(0, 15, 30),
                isAllDay: false,
                notes: "Bring referral documents and water bottle.",
                location: "BBRZ, Vienna",
                calendarTitle: "Personal",
                calendarColorHex: "#22C55E"
            ),
            MockSeed(
                id: "mock-design-review",
                calendarID: "mock-work",
                title: "ChronoSieve UI Design Review",
                startDate: date(1, 14, 0),
                endDate: date(1, 15, 0),
                isAllDay: false,
                notes: "Review grouped glass cards\nFigma: https://figma.com/file/mock-liquid-glass",
                location: "Meeting Room 4B",
                calendarTitle: "Calendar",
                calendarColorHex: "#3B82F6"
            ),
            MockSeed(
                id: "mock-focus",
                calendarID: "mock-personal",
                title: "Focus Block",
                startDate: date(2, 8, 30),
                endDate: date(2, 10, 30),
                isAllDay: false,
                notes: "No meetings. Deep work.",
                location: "Home Office",
                calendarTitle: "Personal",
                calendarColorHex: "#22C55E"
            )
        ]
    }

    private func overlaps(seed: MockSeed, interval: DateInterval) -> Bool {
        seed.startDate < interval.end && seed.endDate > interval.start
    }
}
