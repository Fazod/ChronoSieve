import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityReceiver: NSObject {
    static let shared = WatchConnectivityReceiver()

    private let snapshotKey = "agendaSnapshot"

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
        guard let data = applicationContext["agendaSnapshot"] as? Data else { return }
        UserDefaults.standard.set(data, forKey: "agendaSnapshot")
        NotificationCenter.default.post(name: .agendaSnapshotUpdated, object: nil)
    }
}
