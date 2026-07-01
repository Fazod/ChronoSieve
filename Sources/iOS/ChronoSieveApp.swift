import SwiftData
import SwiftUI

@main
struct ChronoSieveApp: App {
    @StateObject private var viewModel: AgendaViewModel

    private let isUITesting: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        isUITesting = arguments.contains("UI_TESTING")

        if arguments.contains("MOCK_EVENTS") {
            _viewModel = StateObject(wrappedValue: AgendaViewModel(calendarService: MockCalendarService()))
        } else {
            _viewModel = StateObject(wrappedValue: AgendaViewModel())
        }
    }

    var body: some Scene {
        WindowGroup {
            AgendaView(viewModel: viewModel)
        }
        .modelContainer(for: [FilterRuleRecord.self], inMemory: isUITesting)
    }
}
