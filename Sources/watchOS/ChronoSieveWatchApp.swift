import SwiftUI

@main
struct ChronoSieveWatchApp: App {
    @StateObject private var viewModel = WatchAgendaViewModel()
    private let connectivityReceiver = WatchConnectivityReceiver.shared

    var body: some Scene {
        WindowGroup {
            WatchAgendaView(viewModel: viewModel)
        }
    }
}
