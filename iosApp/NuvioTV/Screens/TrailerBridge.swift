import SwiftUI
import UIKit

/// Reports the START of the full-screen cover's dismissal. SwiftUI tells the presenter about a
/// system dismissal (Back) only when it has finished: the cover binding's nil, `onDismiss` and the
/// player teardown all land in the same millisecond (sim log, 2026-09-05), so for the whole
/// dismissal animation the description underneath still shows its "playing" values (black) and the
/// cover crossfades a frozen copy of its content over it. A child view controller inside the cover
/// gets `viewWillDisappear` when the dismissal begins, which is the hook the bridge needs to move
/// the description to its return values in time for the reveal.
struct TrailerBridgeCoverObserver: UIViewControllerRepresentable {
    let onWillDisappear: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onWillDisappear = onWillDisappear
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.onWillDisappear = onWillDisappear
    }

    final class Controller: UIViewController {
        var onWillDisappear: (() -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onWillDisappear?()
        }
    }
}
