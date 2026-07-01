import Foundation
import SwiftData

@Model
final class FilterRuleRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var pattern: String
    var isEnabled: Bool
    var modeRawValue: String
    var isCaseSensitive: Bool
    var targetsRawValue: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        pattern: String,
        isEnabled: Bool = true,
        modeRawValue: String,
        isCaseSensitive: Bool = false,
        targetsRawValue: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.modeRawValue = modeRawValue
        self.isCaseSensitive = isCaseSensitive
        self.targetsRawValue = targetsRawValue
        self.createdAt = createdAt
    }
}

extension FilterRuleRecord {
    convenience init(rule: FilterRule) {
        self.init(
            id: rule.id,
            name: rule.name,
            pattern: rule.pattern,
            isEnabled: rule.isEnabled,
            modeRawValue: rule.mode.rawValue,
            isCaseSensitive: rule.isCaseSensitive,
            targetsRawValue: Self.encodeTargets(rule.targets)
        )
    }

    var mode: FilterMode {
        get { FilterMode(rawValue: modeRawValue) ?? .exclude }
        set { modeRawValue = newValue.rawValue }
    }

    var targets: Set<FilterTarget> {
        get {
            let values = targetsRawValue
                .split(separator: ",")
                .compactMap { FilterTarget(rawValue: String($0)) }

            return Set(values)
        }
        set {
            targetsRawValue = Self.encodeTargets(newValue)
        }
    }

    var asFilterRule: FilterRule {
        FilterRule(
            id: id,
            name: name,
            pattern: pattern,
            isEnabled: isEnabled,
            mode: mode,
            isCaseSensitive: isCaseSensitive,
            targets: targets.isEmpty ? [.title] : targets
        )
    }

    func apply(_ rule: FilterRule) {
        id = rule.id
        name = rule.name
        pattern = rule.pattern
        isEnabled = rule.isEnabled
        mode = rule.mode
        isCaseSensitive = rule.isCaseSensitive
        targets = rule.targets
    }

    private static func encodeTargets(_ targets: Set<FilterTarget>) -> String {
        targets
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    static func makeDefaultBirthdayRule() -> FilterRuleRecord {
        FilterRuleRecord(
            name: "Hide birthdays",
            pattern: "birthday",
            isEnabled: false,
            modeRawValue: FilterMode.exclude.rawValue,
            isCaseSensitive: false,
            targetsRawValue: encodeTargets([.title])
        )
    }
}
