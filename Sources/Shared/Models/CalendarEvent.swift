import Foundation

enum RSVPStatus: String, Codable, Hashable {
    case unknown
    case accepted
    case declined
    case tentative
    case notResponded
}

struct Attendee: Identifiable, Hashable {
    let id: String        // email when available, else name
    let name: String
    let email: String?
    let rsvpStatus: RSVPStatus
    let isOrganizer: Bool
    let isOptional: Bool

    var initials: String {
        let words = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[words.count - 1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let notes: String?
    let location: String?
    let calendarTitle: String
    let calendarID: String
    let calendarColorHex: String
    let rsvpStatus: RSVPStatus
    let attendees: [Attendee]
    let recurrenceDescription: String?
    let isCancelled: Bool
}
