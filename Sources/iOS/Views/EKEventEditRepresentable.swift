import EventKit
import EventKitUI
import SwiftUI

/// Wraps `EKEventEditViewController` as a SwiftUI sheet.
///
/// `EKEventEditViewController` is a `UINavigationController` subclass and must be
/// embedded as a proper child view controller — hosting it directly as a
/// `UIViewControllerRepresentable` root shows only a blank white background because
/// the VC never finishes loading its content without being in the right containment
/// hierarchy. `ContainerVC` handles the embed, then delegates save/cancel back via
/// `EKEventEditViewDelegate` so the parent can dismiss the sheet.
struct EKEventEditRepresentable: UIViewControllerRepresentable {
    let eventStore: EKEventStore
    let event: EKEvent
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> ContainerVC {
        ContainerVC(eventStore: eventStore, event: event, delegate: context.coordinator)
    }

    func updateUIViewController(_: ContainerVC, context _: Context) {}

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

    // MARK: - Container

    /// Thin UIViewController that embeds EKEventEditViewController as a child so its
    /// view hierarchy initialises correctly inside a SwiftUI-managed sheet.
    final class ContainerVC: UIViewController {
        private let eventStore: EKEventStore
        private let event: EKEvent
        private weak var delegate: EKEventEditViewDelegate?

        init(eventStore: EKEventStore, event: EKEvent, delegate: EKEventEditViewDelegate) {
            self.eventStore = eventStore
            self.event = event
            self.delegate = delegate
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        override func viewDidLoad() {
            super.viewDidLoad()

            let editVC = EKEventEditViewController()
            editVC.eventStore = eventStore
            editVC.event = event
            editVC.editViewDelegate = delegate

            addChild(editVC)
            editVC.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(editVC.view)
            NSLayoutConstraint.activate([
                editVC.view.topAnchor.constraint(equalTo: view.topAnchor),
                editVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                editVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                editVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            editVC.didMove(toParent: self)
        }
    }
}
