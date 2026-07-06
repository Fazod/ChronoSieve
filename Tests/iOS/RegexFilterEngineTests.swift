import XCTest
@testable import ChronoSieve

final class RegexFilterEngineTests: XCTestCase {
    func testExcludeRuleHidesMatchingTitle() {
        var engine = RegexFilterEngine()

        let events = [
            makeEvent(id: "1", title: "Team Sync"),
            makeEvent(id: "2", title: "Birthday Party")
        ]

        let rules = [
            FilterRule(
                name: "Hide birthdays",
                pattern: "birthday",
                isEnabled: true,
                mode: .exclude,
                isCaseSensitive: false,
                targets: [.title]
            )
        ]

        let filtered = engine.apply(rules: rules, to: events)

        XCTAssertEqual(filtered.map(\.id), ["1"])
    }

    func testIncludeThenExcludeCombination() {
        var engine = RegexFilterEngine()

        let events = [
            makeEvent(id: "1", title: "Work: Planning"),
            makeEvent(id: "2", title: "Work: Retro"),
            makeEvent(id: "3", title: "Private Dinner")
        ]

        let rules = [
            FilterRule(
                name: "Only work",
                pattern: "^Work",
                isEnabled: true,
                mode: .include,
                isCaseSensitive: true,
                targets: [.title]
            ),
            FilterRule(
                name: "Hide retros",
                pattern: "Retro",
                isEnabled: true,
                mode: .exclude,
                isCaseSensitive: true,
                targets: [.title]
            )
        ]

        let filtered = engine.apply(rules: rules, to: events)

        XCTAssertEqual(filtered.map(\.id), ["1"])
    }

    func testCaseSensitivityIsApplied() {
        var engine = RegexFilterEngine()

        let events = [makeEvent(id: "1", title: "BIRTHDAY")]

        let caseSensitiveRules = [
            FilterRule(
                name: "Case-sensitive",
                pattern: "birthday",
                isEnabled: true,
                mode: .exclude,
                isCaseSensitive: true,
                targets: [.title]
            )
        ]

        let caseInsensitiveRules = [
            FilterRule(
                name: "Case-insensitive",
                pattern: "birthday",
                isEnabled: true,
                mode: .exclude,
                isCaseSensitive: false,
                targets: [.title]
            )
        ]

        let sensitiveResult = engine.apply(rules: caseSensitiveRules, to: events)
        let insensitiveResult = engine.apply(rules: caseInsensitiveRules, to: events)

        XCTAssertEqual(sensitiveResult.count, 1)
        XCTAssertEqual(insensitiveResult.count, 0)
    }

    func testRuleTargetsNotesField() {
        var engine = RegexFilterEngine()

        let events = [
            makeEvent(id: "1", title: "Status", notes: "Contains confidential details"),
            makeEvent(id: "2", title: "Status", notes: "General")
        ]

        let rules = [
            FilterRule(
                name: "Hide confidential",
                pattern: "confidential",
                isEnabled: true,
                mode: .exclude,
                isCaseSensitive: false,
                targets: [.notes]
            )
        ]

        let filtered = engine.apply(rules: rules, to: events)

        XCTAssertEqual(filtered.map(\.id), ["2"])
    }

    func testInvalidPatternValidationFails() {
        var engine = RegexFilterEngine()

        XCTAssertFalse(engine.validate(pattern: "(", caseSensitive: false))
        XCTAssertTrue(engine.validate(pattern: "^work", caseSensitive: false))
    }

    private func makeEvent(
        id: String,
        title: String,
        notes: String? = nil,
        location: String? = nil,
        calendarTitle: String = "Default"
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: Date(timeIntervalSince1970: 1_735_689_600),
            endDate: Date(timeIntervalSince1970: 1_735_693_200),
            isAllDay: false,
            notes: notes,
            location: location,
            calendarTitle: calendarTitle,
            calendarID: "calendar-1",
            calendarColorHex: "#3366FF",
            rsvpStatus: .accepted,
            attendees: [],
            recurrenceDescription: nil,
            isCancelled: false
        )
    }
}
