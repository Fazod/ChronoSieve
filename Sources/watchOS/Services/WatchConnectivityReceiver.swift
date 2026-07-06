import Foundation
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchConnectivityReceiver: NSObject {
    static let shared = WatchConnectivityReceiver()


    private override init() {
        super.init()
        activateIfNeeded()
    }

    private func activateIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
}

extension WatchConnectivityReceiver: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[AgendaSnapshotStore.snapshotKey] as? Data else { return }
        AgendaSnapshotStore.storeShared(data)
        WidgetCenter.shared.reloadTimelines(ofKind: ChronoSieveWidgetKind.dailyAgenda)
        NotificationCenter.default.post(name: .agendaSnapshotUpdated, object: nil)
    }
}
