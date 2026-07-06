import EventKit
import XCTest
@testable import ChronoSieve

@MainActor
final class AgendaViewModelTests: XCTestCase {
    func testInitialRefreshLoadsPastAndFutureDates() async throws {
        let service = CalendarServiceSpy()
        let viewModel = AgendaViewModel(calendarService: service)

        await viewModel.refresh(force: true)

        let interval = try XCTUnwrap(viewModel.loadedInterval)
        let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())

        XCTAssertLessThan(interval.start, today)
        XCTAssertGreaterThan(interval.end, today)
        XCTAssertEqual(service.fetchIntervals.count, 1)
    }

    func testEnsureDateLoadedExtendsRangeBackwardForPastDate() async throws {
        let service = CalendarServiceSpy()
        let viewModel = AgendaViewModel(calendarService: service)
        let calendar = Calendar.autoupdatingCurrent
        let targetDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -120, to: Date()))

        await viewModel.refresh(force: true)
        await viewModel.ensureDateLoaded(targetDate)

        let interval = try XCTUnwrap(viewModel.loadedInterval)

        XCTAssertTrue(interval.contains(targetDate))
        XCTAssertGreaterThanOrEqual(service.fetchIntervals.count, 2)
    }

    func testLoadPreviousIfNeededExtendsRangeBackwardNearStart() async throws {
        let service = CalendarServiceSpy()
        let viewModel = AgendaViewModel(calendarService: service)

        await viewModel.refresh(force: true)
        let initialInterval = try XCTUnwrap(viewModel.loadedInterval)

        await viewModel.loadPreviousIfNeeded(currentDay: initialInterval.start)

        let extendedInterval = try XCTUnwrap(viewModel.loadedInterval)

        XCTAssertLessThan(extendedInterval.start, initialInterval.start)
        XCTAssertEqual(extendedInterval.end, initialInterval.end)
        XCTAssertGreaterThanOrEqual(service.fetchIntervals.count, 2)
    }
}

@MainActor
private final class CalendarServiceSpy: CalendarServiceProtocol {
    private(set) var fetchIntervals: [DateInterval] = []
    private var changeHandler: (() -> Void)?

    func requestAccess() async -> Bool {
        true
    }

    func fetchCalendars() async -> [CalendarSource] {
        [
            CalendarSource(
                id: "calendar-1",
                title: "Work",
                colorHex: "#3366FF",
                accountTitle: "Test"
            )
        ]
    }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) async -> [CalendarEvent] {
        fetchIntervals.append(interval)
        return []
    }

    func moveEvent(_ eventID: String, toCalendarID calendarID: String) async throws {}

    func prepareRSVPEdit(for eventID: String) -> (store: EKEventStore, event: EKEvent)? {
        nil
    }

    func setChangeHandler(_ handler: @escaping () -> Void) {
        changeHandler = handler
    }
}
