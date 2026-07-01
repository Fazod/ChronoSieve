import EventKit
import Foundation
import UIKit

@MainActor
protocol CalendarServiceProtocol {
    func requestAccess() async -> Bool
    func fetchCalendars() async -> [CalendarSource]
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) async -> [CalendarEvent]
    func moveEvent(_ eventID: String, toCalendarID calendarID: String) async throws
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

    func moveEvent(_ eventID: String, toCalendarID calendarID: String) async throws {
        // Strip the recurring-instance suffix (#timestamp) to get the base identifier
        let baseID = String(eventID.split(separator: "#", maxSplits: 1).first ?? Substring(eventID))

        guard let item = eventStore.calendarItem(withIdentifier: baseID),
              let ekEvent = item as? EKEvent
        else {
            throw CalendarServiceError.eventNotFound
        }

        guard let targetCalendar = eventStore.calendar(withIdentifier: calendarID) else {
            throw CalendarServiceError.calendarNotFound
        }

        ekEvent.calendar = targetCalendar
        // For recurring events change the whole series; single events use thisEvent
        let span: EKSpan = (ekEvent.recurrenceRules?.isEmpty == false) ? .futureEvents : .thisEvent
        try eventStore.save(ekEvent, span: span, commit: true)
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
            calendarID: event.calendar.calendarIdentifier,
            calendarColorHex: UIColor(cgColor: event.calendar.cgColor).hexString,
            rsvpStatus: mapRSVPStatus(event),
            attendees: mapAttendees(event),
            recurrenceDescription: mapRecurrenceDescription(event)
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

    private func mapRSVPStatus(_ event: EKEvent) -> RSVPStatus {
        guard let attendees = event.attendees,
              let self_ = attendees.first(where: { $0.isCurrentUser }) else {
            // No attendee list or current user not found — treat as accepted (own event)
            return .accepted
        }
        return mapParticipantStatus(self_.participantStatus)
    }

    private func mapAttendees(_ event: EKEvent) -> [Attendee] {
        guard let participants = event.attendees else { return [] }

        return participants
            .compactMap { participant -> Attendee? in
                let rawEmail = participant.url.absoluteString
                    .replacingOccurrences(of: "mailto:", with: "")
                let email: String? = rawEmail.contains("@") ? rawEmail : nil

                guard let name = participant.name, !name.isEmpty else { return nil }

                return Attendee(
                    id: email ?? name,
                    name: name,
                    email: email,
                    rsvpStatus: mapParticipantStatus(participant.participantStatus),
                    isOrganizer: participant.participantRole == .chair,
                    isOptional: participant.participantRole == .optional
                )
            }
            .sorted { lhs, rhs in
                if lhs.isOrganizer != rhs.isOrganizer { return lhs.isOrganizer }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func mapParticipantStatus(_ status: EKParticipantStatus) -> RSVPStatus {
        switch status {
        case .accepted:  return .accepted
        case .declined:  return .declined
        case .tentative: return .tentative
        case .pending:   return .notResponded
        default:         return .unknown
        }
    }

    private func mapRecurrenceDescription(_ event: EKEvent) -> String? {
        guard let rule = event.recurrenceRules?.first else { return nil }

        let intervalStr = rule.interval > 1 ? " \(rule.interval)" : ""

        switch rule.frequency {
        case .daily:
            return rule.interval == 1 ? "Repeats daily" : "Repeats every \(rule.interval) days"

        case .weekly:
            if let days = rule.daysOfTheWeek, !days.isEmpty {
                let weekdayOrder: [EKWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
                let sorted = days
                    .sorted { (weekdayOrder.firstIndex(of: $0.dayOfTheWeek) ?? 9) < (weekdayOrder.firstIndex(of: $1.dayOfTheWeek) ?? 9) }
                    .map { weekdayFullName($0.dayOfTheWeek) }
                let joined = listJoined(sorted)
                return rule.interval == 1
                    ? "Repeats every week on \(joined)"
                    : "Repeats every \(rule.interval) weeks on \(joined)"
            }
            return rule.interval == 1 ? "Repeats weekly" : "Repeats every\(intervalStr) weeks"

        case .monthly:
            return rule.interval == 1 ? "Repeats monthly" : "Repeats every\(intervalStr) months"

        case .yearly:
            return "Repeats yearly"

        @unknown default:
            return nil
        }
    }

    private func weekdayFullName(_ day: EKWeekday) -> String {
        switch day {
        case .sunday:    return "Sunday"
        case .monday:    return "Monday"
        case .tuesday:   return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday:  return "Thursday"
        case .friday:    return "Friday"
        case .saturday:  return "Saturday"
        @unknown default: return "Unknown"
        }
    }

    private func listJoined(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        let allButLast = items.dropLast().joined(separator: ", ")
        return "\(allButLast) and \(items.last!)"
    }
}

enum CalendarServiceError: Error {
    case eventNotFound
    case calendarNotFound
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
