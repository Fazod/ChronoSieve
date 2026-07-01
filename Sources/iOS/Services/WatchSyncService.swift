import Foundation
import WatchConnectivity

@MainActor
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    private let snapshotKey = "agendaSnapshot"
    private let encoder = JSONEncoder()

    private override init() {
        super.init()
        activateSessionIfNeeded()
    }

    func push(events: [CalendarEvent]) {
        let snapshot = AgendaSnapshot(
            generatedAt: Date(),
            events: events.map(AgendaSnapshotEvent.init(event:))
        )

        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        UserDefaults.standard.set(data, forKey: snapshotKey)

        guard WCSession.default.activationState == .activated else {
            return
        }

        try? WCSession.default.updateApplicationContext([snapshotKey: data])
    }

    private func activateSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
}
