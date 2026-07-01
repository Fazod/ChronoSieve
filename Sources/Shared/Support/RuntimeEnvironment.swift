import Foundation

enum RuntimeEnvironment {
    static let launchArguments = ProcessInfo.processInfo.arguments

    static var isUITesting: Bool {
        launchArguments.contains("UI_TESTING")
    }

    static var usesMockCalendarData: Bool {
        if launchArguments.contains("REAL_CALENDAR") {
            return false
        }

        if launchArguments.contains("MOCK_EVENTS") || isUITesting {
            return true
        }

        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
