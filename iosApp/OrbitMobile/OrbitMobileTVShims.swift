#if !os(tvOS)
import SwiftUI
import UIKit

// Orbit mobile: compile-only stand-ins for the remote's APIs that the shared Apple TV files call
// (SwiftUI marks them unavailable on iOS). They do nothing on a touch screen: a section, a Menu
// press or a D-pad move has no meaning there. They let the shared files compile unchanged for the
// iOS target; this file is in the OrbitMobile target only, so the Apple TV build never sees it.
//
// If Xcode reports an ambiguity on one of these (it should prefer an available declaration over
// SwiftUI's unavailable one), delete that shim and put the call sites listed in README.md under
// `#if os(tvOS)` instead.

/// Stands in for SwiftUI's tvOS/macOS-only type (local types shadow imported ones).
nonisolated enum MoveCommandDirection: Hashable, Sendable {
    case up, down, left, right
}

extension View {
    func focusSection() -> some View { self }
    func onMoveCommand(perform action: ((MoveCommandDirection) -> Void)?) -> some View { self }
    func onExitCommand(perform action: (() -> Void)?) -> some View { self }
    func onPlayPauseCommand(perform action: (() -> Void)?) -> some View { self }
    func focusScope(_ namespace: Namespace.ID) -> some View { self }
    func prefersDefaultFocus(_ prefersDefaultFocus: Bool = true, in namespace: Namespace.ID) -> some View { self }
}

/// tvOS-only UIKit container used by the platform pages' search (`OrbitPlatformSearch.swift`),
/// which the mobile app never shows in v1. A plain container so the file compiles.
final class UISearchContainerViewController: UIViewController {
    let searchController: UISearchController

    init(searchController: UISearchController) {
        self.searchController = searchController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
