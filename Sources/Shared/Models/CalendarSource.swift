import Foundation

struct CalendarSource: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let colorHex: String
    /// The account / source name this calendar belongs to (e.g. "iCloud", "Exchange").
    let accountTitle: String
}
