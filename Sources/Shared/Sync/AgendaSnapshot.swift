import Foundation

struct AgendaSnapshot: Codable {
    var generatedAt: Date
    var events: [AgendaSnapshotEvent]
}

struct AgendaSnapshotEvent: Codable, Identifiable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarTitle: String
}

extension AgendaSnapshotEvent {
    init(event: CalendarEvent) {
        self.id = event.id
        self.title = event.title
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.isAllDay = event.isAllDay
        self.calendarTitle = event.calendarTitle
    }
}
