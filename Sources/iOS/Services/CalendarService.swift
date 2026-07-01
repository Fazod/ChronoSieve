import EventKit
import Foundation
import UIKit

@MainActor
protocol CalendarServiceProtocol {
    func requestAccess() async -> Bool
    func fetchCalendars() async -> [CalendarSource]
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) async -> [CalendarEvent]
    func setChangeHandler(_ handler: @escaping () -> Void)
}

@MainActor
final class CalendarService: CalendarServiceProtocol {
    private let eventStore = EKEventStore()
    private var changeHandler: (() -> Void)?
    private var eventStoreObserver: NSObjectProtocol?

    init() {
        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.changeHandler?()
            }
        }
    }

    deinit {
        if let eventStoreObserver {
            NotificationCenter.default.removeObserver(eventStoreObserver)
        }
    }

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .authorized:
            return true
        case .fullAccess:
            return true
        case .notDetermined:
            do {
                if #available(iOS 17.0, *) {
                    return try await eventStore.requestFullAccessToEvents()
                } else {
                    return try await withCheckedThrowingContinuation { continuation in
                        eventStore.requestAccess(to: .event) { granted, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: granted)
                            }
                        }
                    }
                }
            } catch {
                return false
            }
        case .restricted, .denied, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }

    func fetchCalendars() async -> [CalendarSource] {
        eventStore
            .calendars(for: .event)
            .map {
                CalendarSource(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    colorHex: UIColor(cgColor: $0.cgColor).hexString
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) async -> [CalendarEvent] {
        guard !calendarIDs.isEmpty else {
            return []
        }

        let selectedCalendars = eventStore
            .calendars(for: .event)
            .filter { calendarIDs.contains($0.calendarIdentifier) }

        guard !selectedCalendars.isEmpty else {
            return []
        }

        let queryInterval = makeExpandedQueryInterval(from: interval)
        let predicate = eventStore.predicateForEvents(
            withStart: queryInterval.start,
            end: queryInterval.end,
            calendars: selectedCalendars
        )

        let events = eventStore.events(matching: predicate)
        var uniqueEvents: [String: CalendarEvent] = [:]

        for event in events {
            guard let mapped = mapEvent(event, visibleInterval: interval) else {
                continue
            }

            if let existing = uniqueEvents[mapped.id] {
                if mapped.startDate < existing.startDate {
                    uniqueEvents[mapped.id] = mapped
                }
            } else {
                uniqueEvents[mapped.id] = mapped
            }
        }

        return uniqueEvents.values.sorted { $0.startDate < $1.startDate }
    }

    func setChangeHandler(_ handler: @escaping () -> Void) {
        changeHandler = handler
    }

    private func makeExpandedQueryInterval(from interval: DateInterval) -> DateInterval {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.date(byAdding: .day, value: -1, to: interval.start) ?? interval.start.addingTimeInterval(-86_400)
        let end = calendar.date(byAdding: .day, value: 1, to: interval.end) ?? interval.end.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    private func mapEvent(_ event: EKEvent, visibleInterval: DateInterval) -> CalendarEvent? {
        let normalized = normalizedDates(for: event)

        guard overlaps(interval: visibleInterval, startDate: normalized.startDate, endDate: normalized.endDate) else {
            return nil
        }

        return CalendarEvent(
            id: stableIdentifier(for: event, fallbackStartDate: normalized.startDate),
            title: event.title ?? "(No title)",
            startDate: normalized.startDate,
            endDate: normalized.endDate,
            isAllDay: event.isAllDay,
            notes: event.notes,
            location: event.location,
            calendarTitle: event.calendar.title,
            calendarColorHex: UIColor(cgColor: event.calendar.cgColor).hexString
        )
    }

    private func normalizedDates(for event: EKEvent) -> (startDate: Date, endDate: Date) {
        let calendar = Calendar.autoupdatingCurrent

        let start = event.startDate ?? event.occurrenceDate ?? Date()
        var end = event.endDate ?? start

        if event.isAllDay {
            let normalizedStart = calendar.startOfDay(for: start)
            let normalizedEndCandidate = calendar.startOfDay(for: end)

            if normalizedEndCandidate <= normalizedStart {
                let fallbackEnd = calendar.date(byAdding: .day, value: 1, to: normalizedStart)
                    ?? normalizedStart.addingTimeInterval(86_400)
                return (normalizedStart, fallbackEnd)
            }

            return (normalizedStart, normalizedEndCandidate)
        }

        if end <= start {
            end = start.addingTimeInterval(60)
        }

        return (start, end)
    }

    private func stableIdentifier(for event: EKEvent, fallbackStartDate: Date) -> String {
        let base = event.calendarItemIdentifier

        let isRecurringInstance = event.occurrenceDate != nil || !(event.recurrenceRules ?? []).isEmpty
        guard isRecurringInstance else {
            return base
        }

        let instanceDate = event.occurrenceDate ?? event.startDate ?? fallbackStartDate
        return "\(base)#\(Int(instanceDate.timeIntervalSince1970))"
    }

    private func overlaps(interval: DateInterval, startDate: Date, endDate: Date) -> Bool {
        startDate < interval.end && endDate > interval.start
    }
}

private extension UIColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#888888"
        }

        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
