import Foundation

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
}
