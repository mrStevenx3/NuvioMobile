import SwiftUI
import UIKit

/// beta.18 verdict (BUG-66): tells UIKit, explicitly, which scroll view the top tab bar follows on
/// Home.
///
/// The tester's two Tab Bar Geometry pane photos showed two regimes on ONE device: (A) the bar's
/// frame never moves (minY 46 the whole walk; `isHidden` flips 1 and back 0 while scrolled down —
/// UIKit's own auto-hide, undone by SwiftUI re-applying `.automatic`), and (B) the bar follows
/// Home's rows ScrollView 1:1 (minY → −1431 and back). The reading: nothing in the app ever called
/// `setContentScrollView(_:for:)`, so UIKit falls back to its heuristic ("when no content scroll
/// view is set for an edge, UIKit uses a heuristic to search for a UIScrollView to track",
/// `UIViewController.h`). At a cold launch that search runs BEFORE the pinned hero header mounts
/// and finds the rows scroll view; after a tab switch it re-searches, the rows scroll view now sits
/// below the hero and is not found, and the bar stays pinned. Christian's own Apple TV (hero items
/// cached before Home appears) is always pinned.
///
/// So the association is made explicit and deterministic here, behind an About A/B knob that is ON
/// by default, and `TabBarStateProbe` reports what is tracked (`trk=`) so one pane photo settles
/// whether this was the mechanism.
///
/// What this deliberately does NOT do (the bans in `docs/traces-2026-08-27-bug66-upcoming.md`):
/// no scroll-driven `.toolbarVisibility`, no `.safeAreaInset` hero, no hero-refocus completion
/// scroll. It writes nothing into SwiftUI state, it does not set the deprecated
/// `tabBarObservedScrollView` (read only, for the log), and the only geometry it touches is the
/// pinned container's `contentInsetAdjustmentBehavior` (`.never`; the pinned rows already carry
/// `contentInsets.top == 0`, which the settle corrector depends on — classic is never touched).
enum TabBarContentScrollLink {
    nonisolated static let defaultsKey = "debug.bug66ContentScrollView"

    /// Launch-latched, DEFAULT ON: a missing key is ON; `NO` (the launch-argument String, which
    /// `bool(forKey:)` coerces) or `false` is OFF. Same latch shape as every other probe knob.
    nonisolated static let enabled: Bool = resolveEnabled(UserDefaults.standard)

    nonisolated static func resolveEnabled(_ defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    /// review r1 (P2-1): the controllers that actually receive `setContentScrollView`. Every
    /// `UINavigationController` in the chain is dropped (order preserved): Home sits inside a
    /// `NavigationStack`, and a link set on the navigation controller sticks for the session, so
    /// pages pushed from Home that keep the tab bar (See All, folder, person, entity browse) would
    /// inherit Home's off-screen rows as the tracked scroll view. The SDK says containing
    /// navigation/tab controllers observe the value set on their child, so Home's own hosting
    /// controller is enough.
    nonisolated static func linkTargets(in chain: [UIViewController]) -> [UIViewController] {
        chain.filter { !($0 is UINavigationController) }
    }

    /// The rows `UIScrollView` last linked (weak). Read by `TabBarStateProbe` to label `trk=`.
    nonisolated(unsafe) static weak var homeRowsScrollView: UIScrollView?
}

