import Foundation

enum AgendaSnapshotStore {
    static let snapshotKey = "agendaSnapshot"
    static let watchAppGroupIdentifier = "group.com.fdenk.chronosieve.watch"

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: watchAppGroupIdentifier)
    }

    static func load(preferSharedStore: Bool = false) -> AgendaSnapshot? {
        let stores: [UserDefaults?] = preferSharedStore
            ? [sharedDefaults(), .standard]
            : [.standard, sharedDefaults()]

        for store in stores {
            guard
                let store,
                let data = store.data(forKey: snapshotKey),
                let snapshot = try? decoder.decode(AgendaSnapshot.self, from: data)
            else {
                continue
            }

            return snapshot
        }

        return nil
    }

    static func encode(_ snapshot: AgendaSnapshot) -> Data? {
        try? encoder.encode(snapshot)
    }

    static func store(_ snapshot: AgendaSnapshot, in defaults: UserDefaults = .standard) {
        guard let data = encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func storeShared(_ data: Data, mirrorToStandard: Bool = true) {
        sharedDefaults()?.set(data, forKey: snapshotKey)

        if mirrorToStandard {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }
}

enum AgendaSnapshotPlanner {
    static func todayEvents(
        from snapshot: AgendaSnapshot?,
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AgendaSnapshotEvent] {
        guard let dayInterval = dayInterval(containing: referenceDate, calendar: calendar) else {
            return []
        }

        let events = snapshot?.events ?? []
        return events
            .filter { overlaps(event: $0, interval: dayInterval) }
            .sorted(by: sortEvents)
    }

    static func dayInterval(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DateInterval? {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    static func clampedInterval(
        for event: AgendaSnapshotEvent,
        within interval: DateInterval
    ) -> DateInterval? {
        let start = max(event.startDate, interval.start)
        let end = min(event.endDate, interval.end)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func sortEvents(_ lhs: AgendaSnapshotEvent, _ rhs: AgendaSnapshotEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay && !rhs.isAllDay
        }

        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }

        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func overlaps(event: AgendaSnapshotEvent, interval: DateInterval) -> Bool {
        event.startDate < interval.end && event.endDate > interval.start
    }
}

enum ChronoSieveWidgetKind {
    static let dailyAgenda = "ChronoSieveDailyAgendaWidget"
}
