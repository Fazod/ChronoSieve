import Foundation

enum WatchRange: String, CaseIterable, Identifiable {
    case today
    case next7Days

    var id: String { rawValue }
}

struct WatchDayGroup: Identifiable {
    let day: Date
    let events: [AgendaSnapshotEvent]

    var id: Date { day }
}

@MainActor
final class WatchAgendaViewModel: ObservableObject {
    @Published private(set) var events: [AgendaSnapshotEvent] = []
    @Published private(set) var generatedAt: Date?

    private let snapshotKey = "agendaSnapshot"
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .agendaSnapshotUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadSnapshot()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func onAppear() {
        loadSnapshot()
    }

    func loadSnapshot() {
        guard
            let data = UserDefaults.standard.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(AgendaSnapshot.self, from: data)
        else {
            if RuntimeEnvironment.usesMockCalendarData {
                events = MockCalendarFixtures.events()
                    .map(AgendaSnapshotEvent.init(event:))
                    .sorted(by: { $0.startDate < $1.startDate })
                generatedAt = nil
            } else {
                events = makePlaceholderEvents()
                generatedAt = nil
            }
            return
        }

        generatedAt = snapshot.generatedAt
        events = snapshot.events.sorted(by: { $0.startDate < $1.startDate })
    }

    func events(for range: WatchRange, referenceDate: Date = Date()) -> [AgendaSnapshotEvent] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)

        switch range {
        case .today:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
                return []
            }

            return events.filter {
                overlaps(event: $0, start: startOfToday, end: tomorrow)
            }

        case .next7Days:
            guard
                let start = calendar.date(byAdding: .day, value: 1, to: startOfToday),
                let end = calendar.date(byAdding: .day, value: 8, to: startOfToday)
            else {
                return []
            }

            return events.filter {
                overlaps(event: $0, start: start, end: end)
            }
        }
    }

    func groupedEvents(for range: WatchRange, referenceDate: Date = Date()) -> [WatchDayGroup] {
        let events = events(for: range, referenceDate: referenceDate)
        let grouped = Dictionary(grouping: events) {
            Calendar.current.startOfDay(for: $0.startDate)
        }

        return grouped
            .keys
            .sorted()
            .map { day in
                let events = grouped[day, default: []].sorted(by: sortEvents)
                return WatchDayGroup(day: day, events: events)
            }
    }

    func agendaSections(referenceDate: Date = Date()) -> [WatchDayGroup] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)

        return (0..<8).compactMap { dayOffset in
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            else {
                return nil
            }

            let dayEvents = events
                .filter { overlaps(event: $0, start: day, end: nextDay) }
                .sorted(by: sortEvents)

            guard dayOffset == 0 || !dayEvents.isEmpty else {
                return nil
            }

            return WatchDayGroup(day: day, events: dayEvents)
        }
    }

    private func overlaps(event: AgendaSnapshotEvent, start: Date, end: Date) -> Bool {
        event.startDate < end && event.endDate > start
    }

    private func sortEvents(_ lhs: AgendaSnapshotEvent, _ rhs: AgendaSnapshotEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay && !rhs.isAllDay
        }

        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func makePlaceholderEvents() -> [AgendaSnapshotEvent] {
        let now = Date()
        return [
            AgendaSnapshotEvent(
                id: UUID().uuidString,
                title: "Open iPhone app to sync events",
                startDate: now,
                endDate: now.addingTimeInterval(1800),
                isAllDay: false,
                calendarTitle: "ChronoSieve",
                isCancelled: false
            )
        ]
    }
}
