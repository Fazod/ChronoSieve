import EventKit
import EventKitUI
import SwiftUI

/// Wraps `EKEventEditViewController` as a SwiftUI sheet.
///
/// The system edit view includes an **Availability / Status** row for invitation
/// events, letting the user change their RSVP (Accept / Maybe / Decline).
/// When the user saves or cancels, the delegate fires `onDone`, which the
/// parent uses to set `isPresented = false` and dismiss the sheet.
///
/// After a save the existing `EKEventStoreChanged` observer in
/// `CalendarService` fires automatically, so the agenda refreshes without any
/// extra plumbing.
struct EKEventEditRepresentable: UIViewControllerRepresentable {
    let eventStore: EKEventStore
    let event: EKEvent
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = eventStore
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_: EKEventEditViewController, context _: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            onDone()
        }
    }
}
