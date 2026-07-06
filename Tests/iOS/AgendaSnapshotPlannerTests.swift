import XCTest
@testable import ChronoSieve

final class AgendaSnapshotPlannerTests: XCTestCase {
    func testTodayEventsIncludesOverlappingAndMultiDayEvents() throws {
        let calendar = Calendar.autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: Date())
        let noon = try XCTUnwrap(calendar.date(byAdding: .hour, value: 12, to: startOfToday))
        let lateTonight = try XCTUnwrap(calendar.date(byAdding: .hour, value: 23, to: startOfToday))
        let tomorrowMorning = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: startOfToday))
        let tomorrowNoon = try XCTUnwrap(calendar.date(byAdding: .hour, value: 12, to: tomorrowMorning))
        let yesterdayEvening = try XCTUnwrap(calendar.date(byAdding: .hour, value: -6, to: startOfToday))

        let snapshot = AgendaSnapshot(
            generatedAt: Date(),
            events: [
                makeEvent(id: "overnight", title: "Overnight", start: yesterdayEvening, end: noon),
                makeEvent(id: "today", title: "Today", start: noon, end: lateTonight),
                makeEvent(id: "tomorrow", title: "Tomorrow", start: tomorrowMorning, end: tomorrowNoon)
            ]
        )

        let events = AgendaSnapshotPlanner.todayEvents(from: snapshot, referenceDate: startOfToday)

        XCTAssertEqual(events.map(\.id), ["overnight", "today"])
    }

    func testClampedIntervalTrimsEventToCurrentDay() throws {
        let calendar = Calendar.autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: Date())
        let endOfToday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: startOfToday))
        let tomorrowMorning = try XCTUnwrap(calendar.date(byAdding: .hour, value: 3, to: endOfToday))
        let event = makeEvent(id: "late", title: "Late", start: startOfToday, end: tomorrowMorning)
        let dayInterval = try XCTUnwrap(AgendaSnapshotPlanner.dayInterval(containing: startOfToday, calendar: calendar))

        let clamped = AgendaSnapshotPlanner.clampedInterval(for: event, within: dayInterval)

        XCTAssertEqual(clamped?.start, startOfToday)
        XCTAssertEqual(clamped?.end, endOfToday)
    }

    private func makeEvent(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false) -> AgendaSnapshotEvent {
        AgendaSnapshotEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            calendarTitle: "Calendar",
            location: nil,
            calendarColorHex: "#3366FF",
            isCancelled: false
        )
    }
}
