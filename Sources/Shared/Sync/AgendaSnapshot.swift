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
    var location: String?
    var calendarColorHex: String?
    var isCancelled: Bool

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String,
        location: String? = nil,
        calendarColorHex: String? = nil,
        isCancelled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.location = location
        self.calendarColorHex = calendarColorHex
        self.isCancelled = isCancelled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case startDate
        case endDate
        case isAllDay
        case calendarTitle
        case location
        case calendarColorHex
        case isCancelled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        calendarTitle = try container.decode(String.self, forKey: .calendarTitle)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        calendarColorHex = try container.decodeIfPresent(String.self, forKey: .calendarColorHex)
        isCancelled = try container.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
    }
}

extension AgendaSnapshotEvent {
    init(event: CalendarEvent) {
        self.init(
            id: event.id,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendarTitle,
            location: event.location,
            calendarColorHex: event.calendarColorHex,
            isCancelled: event.isCancelled
        )
    }
}
