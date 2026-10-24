import Combine
import SwiftUI

/// Shared visibility state for the floating glass tab bar's immersive-push signal, plus the
/// FEAT-25 "is Home frontmost" signal below.
///
/// T2 (beta.14 regression fix — retired a signal this class used to combine): this class used to
/// also own `scrolledAway`, a SINGLE shared slot fed by whichever tab root last called
/// `setScrolled(_:)`, folded together with `detailDepth` into one `hidden` bit. That was wrong
/// for two reasons: a single shared slot across four independently-scrolling tabs is
/// last-writer-wins (tab B's scroll position could overwrite tab A's), and `ContentView`'s
/// tab-switch reset (`setScrolled(false)`) could race under the latch and desync `hidden` from
/// the actually-selected tab's real position. It was also long dead for the bar's OWN
/// presentation — round 4 (below, `immersiveHidden`) already stopped the toolbar from reading
/// `hidden` at all. The only real consumer was `isScrolledDown` (BUG-27's Menu-to-top signal),
/// and that was already correctly served by `TabBarScrollAutoHide`'s own per-tab
/// `@State private var hidesBar` — one latch per tab root, not one shared across all four.
/// `scrolledAway`/`setScrolled(_:)`/`hidden` are gone; the per-tab `@State` latch is the real
/// state and always was.
///
/// `detailDepth`: count of "immersive" pushed screens (currently just `DetailView`) stacked on
/// top of the active tab's `NavigationStack`. A depth counter rather than a `Bool` because
/// Detail → More Like This → Detail nests — the bar should only reappear once every pushed
/// immersive screen has been popped, not after the first one.
///
/// Owned as a single instance in `MainTabView` (see that property's own doc comment for why T3
/// made it `@State` rather than `@StateObject`) and read/written by descendants via
/// `@Environment(\.tabBarVisibility)` — a custom environment key (not `@EnvironmentObject`) so
/// views that can be presented *outside* the tab shell (e.g. `DetailView` reached through
/// `DeepLinkTitleView`'s own standalone `NavigationStack`, pushed from a Top Shelf deep link with
/// no tab bar in play at all) fall back to a harmless unconnected default instance instead of
/// crashing for a missing environment object.
@MainActor
final class TabBarVisibility: ObservableObject {
    private var detailDepth = 0 {
        didSet {
            // See `popImmersive`: a drop to 0 publishes on the next turn, a rise publishes now
            // (and cancels a pending zero publish, so 1 → 0 → 1 never shows the bar).
            if detailDepth > 0 { pendingZeroPublish = false }
            if detailDepth > 0 || !pendingZeroPublish { recompute() }
        }
    }

    /// Called from an immersive pushed screen's `.onAppear` (currently `DetailView`).
    func pushImmersive() {
        detailDepth += 1
    }

    /// Called from the same screen's `.onDisappear`. An unmatched call (shouldn't happen, but
    /// SwiftUI view lifecycle edge cases are never fully guaranteed) is a full no-op: the early
    /// return both keeps the depth from going negative (which would take two pops to recover) and
    /// keeps the probe from logging a push/pop cycle that never occurred — the cycle counter
    /// exists to diagnose BUG-66, so a phantom count is worse than none (Codex beta.14 r4).
    func popImmersive() {
        guard detailDepth > 0 else { return }
        // Set BEFORE the write so the depth's `didSet` skips the immediate publish for this drop.
        if detailDepth == 1 { pendingZeroPublish = true }
        detailDepth -= 1
        // Batch A (review r1 P3-5): a folder page popping its depth as a Detail pushes over it can
        // cross 1 → 0 → 1 inside one update cycle (SwiftUI orders the two views' appear/disappear
        // freely). The depth write above is immediate; the hide → show → hide publish it would
        // cause is deferred one runloop turn and dropped if the depth is back above 0 by then
        // (BUG-66's bar blip class). `recompute()` is idempotent, so a real pop publishes once.
        if detailDepth == 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingZeroPublish else { return }
                self.pendingZeroPublish = false
                self.recompute()
                // Review r2 (P3-7): the probes record the pop only when it is published, so a
                // dropped 1 → 0 → 1 crossing never logs a phantom `r=pop`.
                TabBarProbe.recordPop(depthAfter: 0)
                // beta.18 verdict (BUG-66): `r=pop` — what the bar tracks once the last immersive
                // screen is gone (hardware checklist step 3). No-op unless the probe is armed.
                TabBarStateProbe.notePop()
            }
        } else {
            TabBarProbe.recordPop(depthAfter: detailDepth)
        }
    }

    /// BUG-30/66/62 diagnostics only — read-only surface of the depth `immersiveHidden` is
    /// computed from, for the About pane's live tab-bar readout.
    var immersiveDepth: Int { detailDepth }

    /// FEAT-25 (device pass 2026-08-21): whether the HOME tab's root content is the frontmost
    /// surface — false while another tab is selected or an immersive screen is pushed over it.
    /// Exists because neither event fires `onDisappear` on Home's subtree (each tab keeps its
    /// NavigationStack alive across a switch, and a push keeps the stack root mounted), so the
    /// hero's autoplaying trailer kept making sound under Detail pages and in Settings. Published
    /// so `HomeHeroBackdrop` can subscribe imperatively (`onReceive`) — the covered subtree is
    /// still hierarchy-resident (that's the bug) but may not re-render while hidden, so a
    /// render-driven gate could defer teardown exactly when it matters.
    @Published private(set) var homeSurfaceCovered = false

    private var homeTabSelected = true {
        didSet { recomputeHomeCovered() }
    }
    /// ContentView's app-root deep-link cover (Top Shelf) — presented over the whole shell, so
    /// it covers Home without touching tab selection or push depth (Codex beta.14 r8).
    private var rootCoverActive = false {
        didSet { recomputeHomeCovered() }
    }

    /// MainTabView reports selection changes here (Home is tab value 0).
    func setHomeTabSelected(_ selected: Bool) {
        guard homeTabSelected != selected else { return }
        homeTabSelected = selected
    }

    /// MainTabView forwards ContentView's deep-link cover presence here.
    func setRootCoverActive(_ active: Bool) {
        guard rootCoverActive != active else { return }
        rootCoverActive = active
    }

    private func recomputeHomeCovered() {
        let covered = !homeTabSelected || detailDepth > 0 || rootCoverActive
        if homeSurfaceCovered != covered { homeSurfaceCovered = covered }
    }

    /// T3: also drives `immersiveHidden` now — see that property's doc comment for why the write
    /// is guarded to an actual 0↔>0 crossing rather than reassigning on every `detailDepth`
    /// change.
    private func recompute() {
        let hidden = detailDepth > 0
        if immersiveHidden != hidden { immersiveHidden = hidden }
        recomputeHomeCovered()
    }

    /// Device pass round 4 (2026-08-02): the toolbar drives off THIS, not the retired `hidden`.
    /// Toggling `.toolbarVisibility(.hidden)` on scroll and re-showing it later left the system
    /// bar frozen mid-slide on real hardware — clipped at the top until focus moved within it —
    /// through three rounds of transition fixes (.automatic→.visible, dropping the custom
    /// animation). The cure is structural: never toggle visibility for scrolling at all; the
    /// tvOS 26 system bar already minimizes/expands natively as content scrolls (`.automatic`),
    /// so there is no hidden→shown transition left to get stuck. Only the immersive detail push
    /// still force-hides. T2: the retired `hidden`/`scrolledAway` were never read by bar
    /// presentation anyway (that's what made them safe to retire) — `isScrolledDown`, computed
    /// per-tab in `TabBarScrollAutoHide`, remains the BUG-27 Menu-to-top signal, unrelated to bar
    /// presentation.
    ///
    /// T3 (beta.14 regression fix): `@Published`, not computed, and written from `recompute()`
    /// ONLY on an actual 0↔>0 crossing — never reassigned to the same value it already held.
    /// This is what makes `tabBarImmersiveHide()` below narrow: it subscribes to
    /// `$immersiveHidden` specifically, so a redundant same-value write (which `@Published` would
    /// still broadcast — it doesn't dedupe) would otherwise re-resolve `.toolbarVisibility` for
    /// no reason. Before T3 this was a plain computed property read fresh by a modifier that took
    /// the whole `TabBarVisibility` object as a parameter — which meant the modifier's owning
    /// view (`MainTabView`, via `@StateObject`) re-evaluated on EVERY `@Published` change on the
    /// object, including unrelated ones like `homeSurfaceCovered`, and `.toolbarVisibility` got
    /// re-resolved along with it. That's the exact mechanism rounds 1–3 fought blind: the bar
    /// froze mid-slide because its resolved preference kept changing identity underneath an
    /// in-flight system transition, on every tab switch. See `tabBarImmersiveHide()` and
    /// `MainTabView.tabBarVisibility` for the other two pieces of this fix.
    @Published private(set) var immersiveHidden: Bool = false
    /// `popImmersive`'s deferred zero publish is still owed.
    private var pendingZeroPublish = false
}

private struct TabBarVisibilityKey: EnvironmentKey {
    static let defaultValue = TabBarVisibility()
}

extension EnvironmentValues {
    var tabBarVisibility: TabBarVisibility {
        get { self[TabBarVisibilityKey.self] }
        set { self[TabBarVisibilityKey.self] = newValue }
    }
}

/// Applies the detail-push-driven tab-bar auto-hide to one tab's root content. Formerly
/// `ContentView.tabBarAutoHide(_ vis: TabBarVisibility)`, a `private extension View` that took
/// the shared instance as a parameter — T3 (beta.14 regression fix) moved it here as a
/// no-argument modifier instead:
///
/// Reading `tabBarVisibility` via `@Environment` INSIDE this modifier (rather than as a
/// parameter) is what makes each `Tab` closure in `MainTabView` a constant, prunable view value —
/// a parameter of object identity forced the closure to be re-evaluated whenever the object's
/// identity was seen as changing inputs upstream. Combined with `MainTabView` reading
/// `$immersiveHidden` through a narrow `onReceive` rather than the whole object through
/// `@StateObject`, `.toolbarVisibility` can now only re-resolve on an actual `immersiveHidden`
/// publish — i.e. a Detail push/pop — never as a side effect of a tab switch. See
/// `MainTabView.tabBarVisibility`'s own doc comment for the other half of this fix.
private struct TabBarImmersiveHideModifier: ViewModifier {
    @Environment(\.tabBarVisibility) private var vis
    @State private var immersive = false

    /// FEAT-30 Phase 0 spike knob (`-debug.sidebarSpike YES`): resolve the tab bar to a CONSTANT
    /// `.hidden` for the whole session so the hardware can answer two questions the simulator
    /// cannot — whether the hidden bar changes the Home rows viewport away from
    /// `heroPinnedRowsViewportBudget`, and what Menu does at a tab root with no bar to receive
    /// focus. Launch-latched like every other probe knob; release-inert unless passed.
    nonisolated static let sidebarSpike = UserDefaults.standard.bool(forKey: "debug.sidebarSpike")

    /// FEAT-30 / H9: the real, shipping term the spike knob above was standing in for — in Rail mode
    /// (FEAT-30's Sidebar before it) the system tab bar is gone for the whole session and the rail
    /// is the only chrome. The knob stays as an alias (spike OR rail mode ⇒ hidden) so a Phase 0
    /// hardware run can still force the hidden-bar geometry without switching the setting.
    ///
    /// A PLAIN INSTANCE READ evaluated in `body`, deliberately NOT a `nonisolated static let` like
    /// the spike beside it. The mode may only change across `ContentView`'s
    /// `.id(theme|style|visibility|font)` remount — and a remount re-creates VIEWS, not type storage,
    /// so a launch-latched static would keep resolving the old mode until the app was relaunched,
    /// leaving the bar and the rail both on screen (or both off). One `UserDefaults` lookup per
    /// body evaluation is the cost, and this body is already narrow by construction: it
    /// re-evaluates on an `immersiveHidden` publish, i.e. a Detail push/pop, never on a tab switch
    /// or a scroll (see the T3 archaeology on this type and on `TabBarVisibility.immersiveHidden`).
    private var railMode: Bool { true }

    func body(content: Content) -> some View {
        content
            // Round 4 (see TabBarVisibility.immersiveHidden): scroll no longer toggles bar
            // visibility at all — `.automatic` lets the tvOS 26 system bar do its native
            // minimize/expand as content scrolls, and only the immersive detail push
            // force-hides. Rounds 1–3 proved any hidden→shown reshow can freeze mid-slide
            // on hardware (clipped at the top until focus re-entered the bar), so the fix
            // is to not have a reshow.
            .toolbarVisibility((immersive || Self.sidebarSpike || railMode) ? .hidden : .automatic, for: .tabBar)
            // T3: use the PAYLOAD from `onReceive`, not the property — `@Published` emits on
            // willSet, same house rule as HomeView.swift's hero-trailer sync (~L1762-1768:
            // "`@Published` emits on willSet, so use the payload, not the property"). A
            // `@Published` publisher replays its current value to a new subscriber, so no
            // `onAppear` seed is needed here.
            .onReceive(vis.$immersiveHidden) { immersive = $0 }
    }
}

extension View {
    /// Attach to a tab root's content to drive the floating tab bar's immersive-push auto-hide.
    /// No-argument by design (see `TabBarImmersiveHideModifier`'s doc comment) — reads the shared
    /// instance from the environment rather than taking it as a parameter.
    func tabBarImmersiveHide() -> some View {
        modifier(TabBarImmersiveHideModifier())
    }
}

/// BUG-30/66/62 (beta.14): release-safe diagnostics for the tvOS 26 system tab bar's scroll-edge
/// state. Same house pattern as `HomeHeroProbe` (deliberately not `#if DEBUG` — this bar has only
/// ever been seen stuck on a device pass, never in sim) but the readout is a live counter
/// snapshot rather than an event log: `.onScrollGeometryChange` can fire many times a second while
/// scrolling, and a line per fire would spam both the console and whatever ring buffer held it.
/// Everything here is in-memory only for the running process — the BUG-30/66 protocol (walk Home
/// down/up, then run Detail push/pop cycles, then check Settings → About) never spans a
/// relaunch — so nothing here touches UserDefaults or feeds back into the bar's own state.
@MainActor
enum TabBarProbe {
    /// Live read, not the other probes' latched `static let`: those pair with a relaunch-based
    /// capture protocol, while this toggle must take effect in the same session it is flipped in.
    nonisolated static var enabled: Bool { UserDefaults.standard.bool(forKey: "debug.tabBarProbe") }

    /// Stable display order for the About pane — dictionary iteration order isn't.
    static let tabNames = ["Home", "Search", "Library", "Add-ons"]

    struct ScrollState {
        var fireCount = 0
        var lastFireMs = 0
        /// T1: `y`/`i` kept separate (not just the combined residual) so the About-pane readout
        /// can show all three — a tester's photo of `y=… i=… r=…` is what lets a device pass
        /// distinguish "the bar never fired" from "it fired but the residual math is wrong".
        var lastOffsetY: CGFloat = 0
        var lastInsetTop: CGFloat = 0
        var lastResidual: CGFloat = 0
    }

    private(set) static var scrollStates: [String: ScrollState] = [:]
    /// Counts full push→pop round trips (depth back to 0), not raw push/pop calls — the BUG-30/66
    /// hypothesis is stated in terms of "N push/pop cycles", not a raw event tally.
    private(set) static var pushPopCycles = 0

    static func recordScrollFire(tab: String, offsetY: CGFloat, insetTop: CGFloat) {
        guard enabled else { return }
        var state = scrollStates[tab, default: ScrollState()]
        state.fireCount += 1
        state.lastFireMs = HomeHeroProbe.sinceLaunchMs
        state.lastOffsetY = offsetY
        state.lastInsetTop = insetTop
        state.lastResidual = offsetY + insetTop
        scrollStates[tab] = state
    }

    static func recordPop(depthAfter: Int) {
        guard enabled, depthAfter == 0 else { return }
        pushPopCycles += 1
    }
}
