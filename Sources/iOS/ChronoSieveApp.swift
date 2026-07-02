import SwiftData
import SwiftUI

@main
struct ChronoSieveApp: App {
    @StateObject private var viewModel: AgendaViewModel
    @StateObject private var contactsService = ContactsService()

    private let isUITesting: Bool

    init() {
        isUITesting = RuntimeEnvironment.isUITesting
        _viewModel = StateObject(wrappedValue: Self.makeViewModel())
    }

    var body: some Scene {
        WindowGroup {
            AgendaView(viewModel: viewModel)
                .environmentObject(contactsService)
                .task {
                    await contactsService.requestAccess()
                }
        }
        .modelContainer(for: [FilterRuleRecord.self], inMemory: isUITesting)
    }

    private static func makeViewModel() -> AgendaViewModel {
        if RuntimeEnvironment.usesMockCalendarData {
            return AgendaViewModel(calendarService: MockCalendarService())
        }

        return AgendaViewModel()
    }
}
