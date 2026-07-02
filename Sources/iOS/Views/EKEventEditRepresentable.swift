import EventKit
import EventKitUI
import SwiftUI

/// Pushes `EKEventViewController` onto the enclosing SwiftUI `NavigationStack`.
///
/// `EKEventViewController` is a `UITableViewController` subclass — it is designed to
/// be *pushed* onto a navigation stack, not presented modally. For invitation events
/// it renders the native Accept / Maybe / Decline attendance buttons; tapping one
/// sends the response to the calendar server (Exchange, iCloud, etc.) automatically.
///
/// Contrast with `EKEventEditViewController`, which is a `UINavigationController`
/// subclass and produces a blank white screen when hosted inside a SwiftUI sheet.
struct EKEventViewRepresentable: UIViewControllerRepresentable {
    let event: EKEvent

    func makeUIViewController(context: Context) -> EKEventViewController {
        let vc = EKEventViewController()
        vc.event = event
        vc.allowsEditing = true          // shows Edit button + attendance controls
        vc.allowsCalendarPreview = false
        return vc
    }

    func updateUIViewController(_ vc: EKEventViewController, context: Context) {
        vc.event = event
    }
}
