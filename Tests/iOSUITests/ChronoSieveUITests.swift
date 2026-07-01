import XCTest

final class ChronoSieveUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments.append("UI_TESTING")

        addUIInterruptionMonitor(withDescription: "System Alerts") { alert in
            let buttonTitles = ["Don’t Allow", "Don't Allow", "Allow Full Access", "Allow", "OK"]
            for title in buttonTitles {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()
        app.tap()
    }

    func testCanOpenAndCloseRuleManager() {
        let agendaButton = app.buttons["Agenda"]
        XCTAssertTrue(agendaButton.waitForExistence(timeout: 3))
        agendaButton.tap()

        XCTAssertTrue(app.staticTexts["GES: Standup"].waitForExistence(timeout: 5))

        openRuleManager()

        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.tap()

        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: 3))
    }

    func testCanAddRuleFromRuleManager() {
        openRuleManager()

        let addRuleButton = app.buttons["Add Rule"]
        XCTAssertTrue(addRuleButton.waitForExistence(timeout: 3))
        addRuleButton.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("UI Test Rule")

        let patternField = app.textFields["Regex pattern"]
        XCTAssertTrue(patternField.waitForExistence(timeout: 3))
        patternField.tap()
        patternField.typeText("test")

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["UI Test Rule"].waitForExistence(timeout: 3))
    }

    func testInvalidRegexShowsErrorAndDisablesSave() {
        openRuleManager()

        let addRuleButton = app.buttons["Add Rule"]
        XCTAssertTrue(addRuleButton.waitForExistence(timeout: 3))
        addRuleButton.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Invalid Regex Rule")

        let patternField = app.textFields["Regex pattern"]
        XCTAssertTrue(patternField.waitForExistence(timeout: 3))
        patternField.tap()
        patternField.typeText("(")

        XCTAssertTrue(app.staticTexts["Invalid regular expression pattern."].waitForExistence(timeout: 3))

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertFalse(saveButton.isEnabled)

        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        cancelButton.tap()
    }

    private func openRuleManager() {
        let controlsButton = app.buttons["Controls"]
        XCTAssertTrue(controlsButton.waitForExistence(timeout: 5))
        controlsButton.tap()

        let manageRulesButton = app.buttons["Manage Rules"]
        XCTAssertTrue(manageRulesButton.waitForExistence(timeout: 3))
        manageRulesButton.tap()

        XCTAssertTrue(app.navigationBars["Filter Rules"].waitForExistence(timeout: 3))
    }
}
