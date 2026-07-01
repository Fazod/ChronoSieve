import Foundation

enum RSVPStatus: String, Codable, Hashable {
    case unknown
    case accepted
    case declined
    case tentative
    case notResponded
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
    let calendarColorHex: String
    let rsvpStatus: RSVPStatus
}
