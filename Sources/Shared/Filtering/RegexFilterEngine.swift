import Foundation

struct RegexFilterEngine {
    private var regexCache: [String: NSRegularExpression] = [:]

    mutating func apply(rules: [FilterRule], to events: [CalendarEvent]) -> [CalendarEvent] {
        let activeRules = rules.filter(\.isEnabled)
        guard !activeRules.isEmpty else { return events }

        let includeRules = activeRules.filter { $0.mode == .include }
        let excludeRules = activeRules.filter { $0.mode == .exclude }

        var included = events

        if !includeRules.isEmpty {
            included = events.filter { event in
                includeRules.contains { rule in
                    matches(rule: rule, event: event)
                }
            }
        }

        if excludeRules.isEmpty {
            return included
        }

        return included.filter { event in
            !excludeRules.contains { rule in
                matches(rule: rule, event: event)
            }
        }
    }

    mutating func validate(pattern: String, caseSensitive: Bool) -> Bool {
        regex(for: pattern, caseSensitive: caseSensitive) != nil
    }

    private mutating func matches(rule: FilterRule, event: CalendarEvent) -> Bool {
        guard let regex = regex(for: rule.pattern, caseSensitive: rule.isCaseSensitive) else {
            return false
        }

        for field in fields(for: rule.targets, event: event) {
            let range = NSRange(location: 0, length: field.utf16.count)
            if regex.firstMatch(in: field, options: [], range: range) != nil {
                return true
            }
        }

        return false
    }

    private func fields(for targets: Set<FilterTarget>, event: CalendarEvent) -> [String] {
        var values: [String] = []

        if targets.contains(.title) {
            values.append(event.title)
        }
        if targets.contains(.notes), let notes = event.notes {
            values.append(notes)
        }
        if targets.contains(.location), let location = event.location {
            values.append(location)
        }
        if targets.contains(.calendar) {
            values.append(event.calendarTitle)
        }

        return values
    }

    private mutating func regex(for pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        let key = "\(caseSensitive)-\(pattern)"
        if let cached = regexCache[key] {
            return cached
        }

        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        regexCache[key] = compiled
        return compiled
    }
}
