import Foundation

@MainActor
final class MockCalendarService: CalendarServiceProtocol {
    private var changeHandler: (() -> Void)?
    private let referenceDateProvider: () -> Date

    init(referenceDateProvider: @escaping () -> Date = Date.init) {
        self.referenceDateProvider = referenceDateProvider
    }

    func requestAccess() async -> Bool {
        true
    }

    func fetchCalendars() async -> [CalendarSource] {
        MockCalendarFixtures.calendars()
    }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) async -> [CalendarEvent] {
        guard !calendarIDs.isEmpty else { return [] }

        return MockCalendarFixtures.events(referenceDate: referenceDateProvider())
            .filter { calendarIDs.contains(calendarID(for: $0)) }
            .filter { overlaps(event: $0, interval: interval) }
            .sorted(by: { $0.startDate < $1.startDate })
    }

    func moveEvent(_ eventID: String, toCalendarID calendarID: String) async throws {
        // No-op in mock — live data refreshes on next fetch
    }

    func setChangeHandler(_ handler: @escaping () -> Void) {
        changeHandler = handler
    }

    private func calendarID(for event: CalendarEvent) -> String {
        switch event.calendarTitle {
        case MockCalendarFixtures.workCalendar.title:
            return MockCalendarFixtures.workCalendar.id
        case MockCalendarFixtures.personalCalendar.title:
            return MockCalendarFixtures.personalCalendar.id
        case MockCalendarFixtures.birthdaysCalendar.title:
            return MockCalendarFixtures.birthdaysCalendar.id
        case MockCalendarFixtures.travelCalendar.title:
            return MockCalendarFixtures.travelCalendar.id
        default:
            return "unknown"
        }
    }

    private func overlaps(event: CalendarEvent, interval: DateInterval) -> Bool {
        event.startDate < interval.end && event.endDate > interval.start
    }
}
