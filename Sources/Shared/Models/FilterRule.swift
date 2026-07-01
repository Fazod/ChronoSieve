import Foundation

enum FilterMode: String, Codable, CaseIterable {
    case include
    case exclude
}

enum FilterTarget: String, Codable, CaseIterable, Hashable {
    case title
    case notes
    case location
    case calendar
}

struct FilterRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var pattern: String
    var isEnabled: Bool = true
    var mode: FilterMode = .exclude
    var isCaseSensitive: Bool = false
    var targets: Set<FilterTarget> = [.title]
}
