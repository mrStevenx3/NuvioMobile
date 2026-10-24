import Combine
import SwiftUI
import UIKit
import SharedCore

nonisolated enum FocusLeadsRow {
    static let defaultsKey = "home_focus_leads_row"
    /// The gap between Home's catalog cards while this mode is on (Classic rows use 28).
    /// Steven's fork (device pass, wako): tighter, 10 (was 14).
    /// Device pass (Steven: closer, like wako): 6 (was 10, then 14).
    static let cardGap: CGFloat = 6
    /// Escape hatch, read once: `defaults write … debug.focusLeadsEngineScroll -bool YES` gives the
    /// focus engine its own row scroll back (the pre-device-pass-2 behaviour).
    static let engineScrolls = UserDefaults.standard.bool(forKey: "debug.focusLeadsEngineScroll")
    /// The glide that brings the focused card to the leading edge. Short enough to keep up with a
    /// held Right, long enough to read as the row sliding under a fixed selection.
    static let animation = Animation.easeOut(duration: 0.32)

    /// Raw `ScrollPosition.scrollTo(x:)` offset that puts card `index` on the viewport's leading
    /// edge (uniform resting widths before it), clamped to the row's scrollable range. Nil when the
    /// row already rests there.
    static func offset(index: Int, cardWidth: CGFloat, gap: CGFloat, sample: RowHScrollSample) -> CGFloat? {
        guard index >= 0, cardWidth > 0, sample.viewportWidth > 0 else { return nil }
        let leading = CGFloat(index) * (cardWidth + gap)
        let maxOffset = max(0, sample.paddedContentWidth - sample.viewportWidth)
        let target = min(max(leading, 0), maxOffset)
        guard abs(target - sample.paddedVisibleMinX) > 0.5 else { return nil }
        return target - sample.insetLeading
    }

    /// Empty room after a row's last card, so the LAST card can still reach the leading edge
    /// (otherwise the row stops scrolling once its end is on screen). The screen width less the
    /// widest the card can get is always enough; any surplus is just blank space at the row's end.
    @MainActor static func trailingRoom(expandedCardWidth: CGFloat, gap: CGFloat) -> CGFloat {
        max(0, UIScreen.main.bounds.width - expandedCardWidth - gap)
    }
}

// MARK: - Home geometry probes (BUG-30 / BUG-37)

/// Runtime knob shared by every Home geometry probe — all of them log with the `[HomeScrollProbe]`
/// prefix, so one device walk produces one greppable stream:
///
///     defaults write com.nuvio.media.NuvioTV debug.homeScrollProbe -bool YES
///
/// Read ONCE at launch: a disabled probe costs a single Bool for the whole session, because every
/// probe is a modifier that simply isn't attached when this is false (see `pinnedRowTitleTracking`
/// here and `HomeScrollProbeModifier` in HomeView).
///
/// Deliberately NOT `#if DEBUG`, matching the existing BUG-30 probe it now backs: there is no
/// automated input path to the physical Apple TV, so every device pass is a manual walk that may
/// well be a release-configuration sideload, and the console is the only diagnostic that comes
/// back (same precedent as `ProfilesViewModel.select(_:)`).
enum HomeGeometryProbe {
    nonisolated static let enabled = UserDefaults.standard.bool(forKey: "debug.homeScrollProbe")
}

// MARK: - Pinned row title tracking (BUG-37)

/// Keeps a PINNED row's overlaid section title inside the rows viewport at every rest position the
/// DEVICE produces, not just the exact ones the simulator produces.
///
/// Why round 8's compromise wasn't enough. The title is overlaid `heroPinnedRowTitleInset` (48)
/// below the SHELF's top; the focusable card frame the engine's scroll-to-reveal aligns starts
/// `Spacing.lg` (24) below that same shelf top, inside the shelf's own padding. So the static
/// margin between "the engine rested the card frame's top at the viewport edge" and "the title's
/// top" is 48 − 24 = 24pt — round 8 read the inset against the shelf and recorded it as ~48. The
/// device's measured rest error is 40–67pt short (`[HomeScrollProbe]`, 1,603 samples, 2026-08-02:
/// rest y=-90 vs true top -157), so the title clears on the sim and is cut on hardware.
///
/// Why NOT card-anchoring the title (moving it inside the button's label), which is the obvious
/// "it moves with the card" fix. It buys nothing here: the shelf never scrolls vertically, so the
/// title and the cards are already rigid with respect to each other — re-anchoring changes which
/// edge the inset is measured from, not the geometry. The band above the art is 96pt whichever
/// anchor you pick, the title is ~40pt, so the best static margin either way is ~32pt, still under
/// the envelope. And it would spend the structural invariants rounds 5–7 paid for: label content
/// has to be compensated by paddings that stay POSITIVE (negative compensation put focusable
/// frames outside their `.focusSection()` and froze directional resolution), a per-card overlay
/// would draw the title once per card, and any extra band means a reach above 72 — the sim
/// bisected 100 as where focus resolution dies.
///
/// What happens instead: the title stays exactly where round 8 put it at a true rest, and slides
/// DOWN by however much the viewport's top edge has eaten into it, clamped to
/// `heroPinnedRowTitleMaxSlide`. BUG-61 (beta.12) changed the HOW, not the WHAT: the slide is now
/// measured via `onGeometryChange` and applied as an eased offset (see `PinnedRowTitleTracking`)
/// instead of a draw-time `visualEffect`, because the draw-time recompute snapped the title in one
/// frame whenever a focus-driven reveal shifted layout discretely. The `@State` this introduces is
/// change-gated and confined to the title's own subtree — rows resting clear of the clip edge
/// measure a constant 0 and write nothing, so the BUG-19 no-identity-churn rule still holds. At
/// 0pt of rest error nothing moves and the look is byte-identical to beta.10; across the whole
/// 0–67pt envelope the title parks against the clip edge instead of disappearing behind it; past
/// the clamp (a row scrolled well above the focused one) it releases and scrolls away like any
/// other content, i.e. it behaves as a sticky header for exactly as long as its row is on screen.
///
/// Contract note for `CollectionRowView` (CollectionsUI.swift, same overlay pattern via the same
/// environment values): the contract is UNCHANGED — the title is still an overlay on the shelf at
/// the same inset — so that row keeps working untouched, it simply keeps the round-8 behavior. The
/// follow-up is one line: add `.pinnedRowTitleTracking(rowKey: collection.id)` to its overlaid
/// `Text` immediately before the existing `.padding(.top, Theme.Size.heroPinnedRowTitleInset)`.
enum PinnedRowTitle {
    /// Name Home attaches to its rows ScrollView (`rowsScroll`) purely as a resolution fallback
    /// for `visibleBounds` below. Also the name `CollectionRowView`'s follow-up inherits for free.
    nonisolated static let rowsScrollSpace = "home_rows_scroll"

    /// The rows viewport's rect, converted into the TITLE's local space — so `minY > 0` reads
    /// directly as "the viewport's top edge is this far BELOW the title's top", i.e. exactly this
    /// much of the title is currently clipped away.
    ///
    /// Primary lookup is the enclosing VERTICAL scroll view (the row's own shelf is horizontal, so
    /// the axis filter skips it). The named fallback covers the case where that filter doesn't
    /// resolve through the nested shelf: a miss on both is fail-safe (no slide = exactly today's
    /// behavior) but silent, so the probe logs nothing for titles — which is itself the signal
    /// that the lookup, not the geometry, is what needs looking at.
    nonisolated static func visibleBounds(_ proxy: GeometryProxy) -> CGRect? {
        proxy.bounds(of: .scrollView(axis: .vertical)) ?? proxy.bounds(of: .named(rowsScrollSpace))
    }

    /// BUG-53/BUG-60 device calibration (beta.12): the whole cluster's remaining dial — how far a
    /// title may ride over its row's artwork — is a function of the DEVICE's rest error, which the
    /// sim cannot reproduce (sim rests park the title clear of the art; the 40–67pt device error
    /// parks it 8–35pt onto it, and under the focused card's system lift). Rather than shipping a
    /// blind constant into the most regression-prone surface, the clamp is overridable at runtime.
    /// Simulator:
    ///
    ///     xcrun simctl spawn <udid> defaults write com.nuvio.media.NuvioTV debug.pinnedTitleMaxSlide -float 40
    ///
    /// Physical Apple TV (Codex gate 1: `defaults write` on the Mac never reaches the device's
    /// sandbox) — pass it as a LAUNCH ARGUMENT; `UserDefaults.standard` consults the argument
    /// domain (`-key value` argv pairs) before every other domain, so this same read picks it up:
    ///
    ///     xcrun devicectl device process launch --terminate-existing --device <udid> \
    ///         com.nuvio.media.NuvioTV -debug.pinnedTitleMaxSlide 40
    ///
    /// so the manual device pass can bisect the visible trade (title clipping at the top vs title
    /// riding over art) live, without rebuild cycles. Unset/0 = the shipped constant. Read once at
    /// launch, same as every other probe knob.
    nonisolated static let maxSlideOverride: CGFloat? = {
        let v = UserDefaults.standard.double(forKey: "debug.pinnedTitleMaxSlide")
        return v > 0 ? CGFloat(v) : nil
    }()

    /// The slide cap resolved for ONE row, in that row's own units.
    ///
    /// Wave 4 item 6 (tester report `docs/steven-batch-plan-2026-08-29.md`, "the section title
    /// slides down over the cards", worst on his Streaming Services collection folder tiles): the
    /// cap used to be the bare `heroPinnedRowTitleMaxSlide` (72) — a fixed number with no knowledge
    /// of the card it rides over. The slide is not what the viewer judges, though; the INTRUSION is
    /// — how far the title's bottom edge ends up past the artwork's top edge:
    ///
    ///     clearance = artworkTop − (titleInset + titleHeight)
    ///               = (Spacing.lg + reach) − (48 + ~38)
    ///               = (24 + 88) − 86  ≈  26pt          // static gap, title bottom → art top
    ///     intrusion = slide − clearance                //  = 46pt at the old fixed 72 cap
    ///
    /// and 46pt is 16.7% of a Small poster's 275pt art, 22.7% of a 203pt landscape card, and 25.1%
    /// of a Small square/landscape FOLDER TILE (183pt — `FolderTile.artworkHeight` takes the height
    /// of those shapes from `style.width`, correctly: they are a true square / true 16:9 of the
    /// row's width, so they are simply SHORTER than a poster). On a folder tile that slice lands on
    /// a centred wordmark rather than a poster's usually-empty top margin. Full arithmetic table in
    /// `Theme.Size.heroPinnedRowTitleArtIntrusionFraction`.
    ///
    /// So the cap becomes proportional to the artwork it rides over:
    ///
    ///     cap = min(heroPinnedRowTitleMaxSlide,
    ///               clearance + artworkHeight × heroPinnedRowTitleArtIntrusionFraction)
    ///
    /// i.e. the intrusion is capped at 9% of the row's art while the proven 72pt absolute still
    /// bounds everything (a very tall row can never buy a bigger slide than the focus band was ever
    /// shown to tolerate). Because the cap is `clearance + budget` it can never fall BELOW the
    /// clearance a settled rest needs — the deterministic beta.12 rest (title bottom exactly at the
    /// art top) is byte-identical at every Poster Size; only deeply-clipped rows give up slide.
    ///
    /// `titleHeight` comes from the title's own proxy rather than a constant, so Bold Text and
    /// larger type shrink the clearance term the same way they shrink the real gap. `artworkHeight`
    /// is nil for a call site that cannot size itself confidently — then only the absolute cap
    /// applies, i.e. exactly the pre-Wave-4 behavior. `cardTopReach` is the row's reach band; the
    /// `Spacing.lg` half of `artworkTop` is the shelf's own vertical padding, which every pinned
    /// row shares (CatalogRowView / UpcomingRow / Continue Watching `.padding(.vertical, .lg)`,
    /// CollectionRowView `.padding(.top, .lg)` in pinned mode).
    ///
    /// `maxSlideOverride` deliberately BYPASSES the proportional term: that knob exists so a manual
    /// device pass can bisect the visible trade live, and a clamp that silently overrode it would
    /// make the knob a no-op at every value above the proportional cap.
    ///
    /// PROBE-ONLY as of Codex 2026-08-29 P1: `slide()` no longer clamps with this value — binding
    /// a sub-absolute cap clips the title at deep rests (visibility beats bounded intrusion). The
    /// probe still reports it as `cap=` so hardware passes can quantify per-row intrusion.
    nonisolated static func maxSlide(titleHeight: CGFloat,
                                     artworkHeight: CGFloat?,
                                     cardTopReach: CGFloat) -> CGFloat {
        if let override = maxSlideOverride { return override }
        let absolute = Theme.Size.heroPinnedRowTitleMaxSlide
        guard let artworkHeight, artworkHeight > 0 else { return absolute }
        let intrusionBudget = artworkHeight * Theme.Size.heroPinnedRowTitleArtIntrusionFraction
        return min(absolute, staticClearance(titleHeight: titleHeight, cardTopReach: cardTopReach) + intrusionBudget)
    }

    /// How far the title's BOTTOM edge sits above the artwork's TOP edge at a true rest (slide 0)
    /// — the free travel a slide has before it starts painting on the card:
    ///
    ///     clearance = artworkTop − titleBottom
    ///               = (Spacing.lg + reach) − (titleInset + titleHeight)
    ///               = (24 + 88) − (48 + ~38)  ≈  26pt
    ///
    /// and therefore `intrusion = slide − clearance` exactly. Factored out of `maxSlide` (which has
    /// computed it inline since Wave 4) so the settle re-reveal targets the SAME number rather than
    /// a second, drifting copy of the arithmetic — Codex r1 P1: gating the correction on raw
    /// `margin < 0` fired on a `margin=-25 net=0` rest whose title was still fully clear of the
    /// art, and would have nudged ordinary Medium/Small rests (`margin=-40 slide=40 net=0`).
    ///
    /// `titleHeight` is the title's own MEASURED height, not a constant, so Bold Text and larger
    /// type shrink this the same way they shrink the real gap.
    ///
    /// This is the AT-REST number. What the viewer judges is the FOCUSED card's clearance — see
    /// `Clearances` — because the card the title rides over is the one the system lift has raised.
    nonisolated static func staticClearance(titleHeight: CGFloat, cardTopReach: CGFloat) -> CGFloat {
        let artworkTop = Theme.Spacing.lg + cardTopReach
        return max(artworkTop - (Theme.Size.heroPinnedRowTitleInset + titleHeight), 0)
    }

    /// One row's two clearances. Both are "title bottom → artwork top at slide 0"; they differ by
    /// which card is being measured against (Codex r4 P1).
    ///
    ///     atRest     = (Spacing.lg + reach) − (titleInset + titleHeight)   ≈ 26pt
    ///     focused    = max(atRest − lift, 0)
    ///     focusedRaw = atRest − lift                                       (BUG-87/89, unclamped)
    ///
    /// The focus treatment raises the FOCUSED card's artwork while the title stays put, so the
    /// card the title actually rides over has that much less room than the row's resting geometry
    /// suggests. Every version before r4 targeted `atRest`, which meant the corrected fixpoint
    /// still left the focused card's artwork under the title — a passing gate alongside the
    /// tester's reported overlap. The correction budget and the visibility belt both work in
    /// `focused` now; `atRest` survives as the probe's pre-lift reading, as the clearance an
    /// UNFOCUSED row is judged by (nothing has raised its cards — Codex r7 P2), and as the term
    /// `maxSlide`'s (probe-only) proportional cap has always used.
    // `nonisolated`: same @Sendable-transform requirement as `Reading` below.
    nonisolated struct Clearances: Equatable, Sendable {
        var atRest: CGFloat
        var focused: CGFloat
        /// What was subtracted — `focusLiftAllowance` for the ACTIVE focus mode. Carried so the
        /// settle log can name it: `focused` alone hides the magnitude once the clamp bites.
        var lift: CGFloat
        /// BUG-87/89: `focused` is CLAMPED at 0 because both consumers — the corrector's `bandLow`
        /// and the belt's `intrusion` — are written in "how much slide is free" units, where a
        /// negative free travel is meaningless. That clamp is also how an 18pt PERMANENT overlap at
        /// Large read as a clean 0 for a whole release. This is the unclamped value: negative means
        /// the focused card's artwork sits that far OVER the settled title's bottom at every rest,
        /// which no correction can fix. Reported on every settle line as `clearanceLiftRaw=`, and
        /// `PinnedRowGeometry.topReachFloor(lift:titleHeight:)` is where it is kept non-negative —
        /// against the ACTIVE font's title metric as of rc10, which is what stopped Open Sans from
        /// reproducing the exact deficit that floor exists to remove.
        var focusedRaw: CGFloat
    }

    /// Which focus treatment a ROW's cards actually wear. Since BUG-108 every pinned row's cards
    /// resolve through `CardFocusMode` — the collection folder row's `FolderTile` now carries
    /// `CardArtworkFocusLift` too (`PlainLabelRing.lift`) — so there is only the one case left; kept
    /// as an enum rather than collapsed away because `focusLiftAllowance`'s and
    /// `pinnedRowTitleTracking`'s signatures still take a `treatment:` and a future row shape may
    /// need a second case again.
    // `nonisolated`: same @Sendable-transform requirement as `Reading` below.
    nonisolated enum RowCardTreatment: Equatable, Sendable {
        /// Cards that go through `CardFocusTreatment` (or, for `FolderTile`/`CastCard`,
        /// `CardArtworkFocusLift` directly via `PlainLabelRing.lift`), so their lift follows
        /// `CardFocusMode.resolve` in all three modes: `PosterCard` (catalog rows, PosterCard.swift
        /// ~L604), `LandscapeCard` (Continue Watching, Upcoming — PosterCard.swift ~L766), and the
        /// collection folder-tile row (`CollectionsUI.swift`) since BUG-108.
        case cardTreatment
    }

    /// The two Appearance settings `CardFocusMode.resolve` branches on, carried as a value so the
    /// lift computation can be driven by a REACTIVE read rather than by whatever the defaults
    /// happened to say the last time geometry moved (Codex r10 P2).
    ///
    /// The staleness this closes: flipping "No Zoom on Focus" or the accent ring in Settings and
    /// coming back to Home changes no geometry — Home is alive in the tab view and its rows have
    /// not moved — so the title's `onGeometryChange` transform need never run again, and the
    /// clearance published to `PinnedRowSettle` would keep describing the PREVIOUS mode
    /// indefinitely: wrong correction target, wrong fade threshold, until something happened to
    /// scroll. `PinnedRowTitleTracking` reads both keys as `@AppStorage` and republishes on change;
    /// see `current` for what the remaining bare reads are for.
    // `nonisolated`: same @Sendable-transform requirement as `Reading` below.
    nonisolated struct FocusModeFlags: Equatable, Sendable {
        var noZoom: Bool
        var accentRing: Bool
        /// BUG-87 rc12 follow-up: the No Zoom reach hold (`AboutSettingsPane`'s "No Zoom Row Reach
        /// (A/B)" row, backing key `PinnedRowTitle.noZoomReachHoldsLiftKey`). The memberwise default
        /// stays `false` for source compatibility, but the APP default is ON since 2026-09-30
        /// (device A/B decided it); app call sites resolve it via `resolveReachHoldsLift`. See
        /// `reachHoldsLiftEffective` for the gate and `PinnedRowGeometry.plan`'s `floorLift` for
        /// where this actually spends — never through `focusLiftAllowance` below.
        var reachHoldsLift: Bool = false

        /// Inert unless `noZoom` is also true, exactly like `accentRing`'s inertness with zoom on:
        /// the hold only means something when No Zoom's own treatment is the reason the reach floor
        /// would otherwise reserve zero room for a lift.
        nonisolated var reachHoldsLiftEffective: Bool { reachHoldsLift && noZoom }

        /// BUG-87/89 zoom-on reach hold (2026-09-30, `zoom-on-title-fix-plan.md` option A; backing
        /// key `PinnedRowTitle.zoomReachHoldKey`, no Settings row yet). Memberwise default `false`
        /// for source compatibility — the APP default is ON, resolved via `resolveZoomReachHold`.
        /// When effective, `PinnedRowGeometry.plan` raises the top-reach floor by
        /// `Theme.Size.heroPinnedRowZoomReachHold` (capped at `heroPinnedRowTopReachHoldCap`) so
        /// the engine's own −12 rest lands inside the zoom-on band. Like `reachHoldsLift`, it never
        /// reaches `focusLiftAllowance`: the lift is unchanged, only the reach grows.
        var zoomReachHold: Bool = false

        /// The mirror of `reachHoldsLiftEffective`: inert in No Zoom, whose own hold already rests
        /// in band (the extra 6pt would only cost rest range there).
        nonisolated var zoomReachHoldEffective: Bool { zoomReachHold && !noZoom }

        /// Live snapshot for call sites with no SwiftUI context to observe from. This is the
        /// DEFAULT, not the primary path: every call that matters — `reading` from the tracking
        /// modifier, and the probe — is handed explicit `@AppStorage`-backed flags, and it is the
        /// modifier-side republish that keeps `PinnedRowSettle.clearances` coherent with them.
        nonisolated static var current: FocusModeFlags {
            FocusModeFlags(noZoom: UserDefaults.standard.bool(forKey: "no_zoom_on_focus"),
                           accentRing: UserDefaults.standard.bool(forKey: "accent_focus_ring"),
                           reachHoldsLift: resolveReachHoldsLift(),
                           zoomReachHold: resolveZoomReachHold())
        }
    }

    /// Backing key for the rc12 No Zoom reach-hold A/B (`FocusModeFlags.reachHoldsLift`,
    /// `AboutSettingsPane`'s "No Zoom Row Reach (A/B)" toggle, `PinnedRowTitleTracking`'s
    /// `@AppStorage`).
    nonisolated static let noZoomReachHoldsLiftKey = "debug.pinnedNoZoomReachHoldsLift"

    /// Launch-latched twin of the `@AppStorage` reads, resolved via `bool(forKey:)` rather than
    /// `@AppStorage<Bool>` because the latter does not coerce a UI test's argument-domain "YES" the
    /// way `bool(forKey:)` does — same precedent as `AboutSettingsPane`'s
    /// `collectionFrameProbe || CollectionFocusFrameProbe.enabled`. Every SwiftUI reader ORs this in
    /// alongside its own `@AppStorage` read so a UI test's launch argument and a live Settings flip
    /// both work.
    nonisolated static var reachHoldsLiftKnob: Bool {
        resolveReachHoldsLift()
    }

    /// Default ON since 2026-09-30 (BUG-87 device A/B: hold OFF gave 50+ `UNEXPECTED-WITH-FIT`
    /// nudges and title fades, hold ON gave none). TRUE when the key was never written; otherwise
    /// `bool(forKey:)`, which also coerces a UI test's argument-domain "YES"/"NO" string.
    nonisolated static func resolveReachHoldsLift(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: noZoomReachHoldsLiftKey) == nil ? true : defaults.bool(forKey: noZoomReachHoldsLiftKey)
    }

    /// View-side form: referencing the `@AppStorage` value keeps the view observing the key so a
    /// toggle flip re-renders; the resolved value is what is used.
    nonisolated static func resolveReachHoldsLift(observing stored: Bool) -> Bool {
        _ = stored
        return resolveReachHoldsLift()
    }

    /// Backing key for the zoom-on reach hold (`FocusModeFlags.zoomReachHold`, 2026-09-30). No
    /// About row today; a UI test flips it with `-debug.pinnedZoomReachHold NO`.
    nonisolated static let zoomReachHoldKey = "debug.pinnedZoomReachHold"

    /// Default ON: TRUE when the key was never written; otherwise `bool(forKey:)`, which also
    /// coerces a UI test's argument-domain "YES"/"NO" string. Same shape as `resolveReachHoldsLift`.
    nonisolated static func resolveZoomReachHold(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: zoomReachHoldKey) == nil ? true : defaults.bool(forKey: zoomReachHoldKey)
    }

    /// View-side form: referencing the `@AppStorage` value keeps the view observing the key; the
    /// resolved value (launch argument and never-written default included) is what is used.
    nonisolated static func resolveZoomReachHold(observing stored: Bool) -> Bool {
        _ = stored
        return resolveZoomReachHold()
    }

    /// How far the ACTIVE focus treatment raises a focused card's artwork.
    ///
    /// Two values, not three (BUG-93, Wave F agent A). `CardFocusMode.resolve` still has three
    /// branches, but only one of them lifts by a different amount, and it is the zero one:
    ///
    ///  - **still** (`no_zoom_on_focus` on, either ring state) — Wave 7 made this genuinely zero
    ///    lift: a custom `ButtonStyle` that never receives the system hover effect, and a treatment
    ///    that draws a border and a shadow and scales nothing. Charging 20pt here fabricated 20pt
    ///    of intrusion out of nothing: every rest was over-corrected by 20pt and titles that were
    ///    perfectly clear could be faded out by the belt.
    ///  - **systemLift** (both off) — the native hover effect on the artwork container, measured at
    ///    `heroPinnedRowFocusLiftAllowance` (test44, 2026-08-25).
    ///  - **manualScale** (ring on, zoom on) — the SAME rise, by construction as of BUG-93.
    ///
    /// The manual branch used to derive its rise from a fixed lockup SCALE (1.12), which made ring
    /// mode charge ~16pt at Small, ~20 at Medium and ~27 at Large against a clip budget that had
    /// reserved 20 everywhere — the "posters cut off at the top" half of BUG-93. PosterCard now
    /// holds the RISE as the constant (`cardFocusLiftRise`, which IS
    /// `Theme.Size.heroPinnedRowFocusLiftAllowance`) and derives the per-card scale from it
    /// (`cardLiftScale(artworkHeight:)`), so both zoom modes raise the artwork's top edge by
    /// exactly 20pt at every Poster Size and this function has nothing left to branch on. The two
    /// sides cannot drift: they are literally the same constant, and test49 measures the ring-mode
    /// rise against it on the sim.
    ///
    /// `mode` is read at MEASUREMENT time from the plain `UserDefaults` key the treatments use as
    /// `@AppStorage`, not latched at launch: "No Zoom on Focus" is a live Appearance toggle. A
    /// settings change therefore takes effect on the row's next reading pass rather than instantly
    /// — the same frame the cards themselves re-render in, so nothing can be seen mid-flip.
    ///
    /// `artworkHeight`, `captionVisible` and `treatment` no longer participate. They are kept in
    /// the signature deliberately rather than removed: every caller already threads them (they are
    /// the same values `maxSlide` and `clearances` need), the ring's rise was height-dependent as
    /// recently as beta.17, and a future treatment that is height-dependent again should not have
    /// to be re-threaded through four call sites to say so.
    ///
    /// `mode.reachHoldsLift` (BUG-87 rc12 follow-up) never reaches this function, on purpose: this
    /// still returns 0 in No Zoom whether or not the hold is on. The hold's job is to reserve ROOM
    /// in the reach for a lift that still-mode genuinely never produces — charging that lift here
    /// too would raise `lift` AND the reach floor for the same 20pt, leaving `bandLow` at −4
    /// (`focused = atRest − lift`) exactly as before the hold existed: the Wave 7 / BUG-93
    /// fabricated-intrusion bug, reintroduced. `PinnedRowGeometry.plan`'s `floorLift` is the one and
    /// only place `reachHoldsLiftEffective` is read.
    nonisolated static func focusLiftAllowance(artworkHeight: CGFloat?,
                                               captionVisible: Bool,
                                               treatment: RowCardTreatment,
                                               mode: FocusModeFlags = .current) -> CGFloat {
        // No-zoom wins over the ring everywhere, checked first exactly as `CardFocusMode.resolve`
        // does. Card treatments get `.still` (nothing scales); folder tiles get
        // `cardFocusButtonStyle`'s `StillCardButtonStyle` + `focusEffectDisabled`, which likewise
        // cannot lift. Every other combination — system lift, ring, and (since BUG-108) the folder
        // tile's own manual scale — rises by the one measured constant.
        mode.noZoom ? 0 : Theme.Size.heroPinnedRowFocusLiftAllowance
    }

    /// Vertical chrome a poster lockup carries BELOW its artwork: `Theme.Spacing.md` (16,
    /// `PosterCard`'s artwork↔caption gap) plus one `Theme.Font.cardTitle` caption line (≈27.5 as
    /// rendered). ≈43.5pt, which is exactly the residue in the 2026-08-30 measurement of the
    /// focusable link frame — `artworkHeight + 175.5` = topReach (88) + lockup + bottomReach (44)
    /// ⇒ lockup = artworkHeight + 43.5.
    ///
    /// No longer feeds any lift arithmetic (BUG-93 moved the focus scale onto the artwork
    /// container, so nothing scales the lockup any more). It survives as the LOCKUP EXTENT every
    /// pinned-row height calculation needs — `HomeView.pinnedLastRowHeight` (BUG-89's trailing
    /// inset) sizes the last row with it, and the settle corrector's band reads the same extent off
    /// the measured row frame. A constant rather than a live type metric for the same reason as
    /// before: it is used to size a BAND, never to lay out the caption itself, and mixed-shape
    /// collection rows (whose tiles use `Spacing.sm` and a per-folder `hideTitle`) are approximated
    /// by the same number.
    nonisolated static let cardLockupCaptionChrome: CGFloat = 43.5

    nonisolated static func clearances(titleHeight: CGFloat,
                                       cardTopReach: CGFloat,
                                       artworkHeight: CGFloat?,
                                       captionVisible: Bool,
                                       treatment: RowCardTreatment,
                                       mode: FocusModeFlags = .current) -> Clearances {
        let atRest = staticClearance(titleHeight: titleHeight, cardTopReach: cardTopReach)
        let lift = focusLiftAllowance(artworkHeight: artworkHeight,
                                      captionVisible: captionVisible,
                                      treatment: treatment,
                                      mode: mode)
        return Clearances(atRest: atRest,
                          focused: max(atRest - lift, 0),
                          lift: lift,
                          focusedRaw: atRest - lift)
    }

    /// How far the title must ride DOWN to stay fully inside the rows viewport, clamped.
    /// `proxy` must be the TITLE's own geometry (local origin = the title's top-left, `size` = the
    /// title's own rendered size). The defaults reproduce the pre-Wave-4 clamp exactly, so any call
    /// site that cannot state its artwork height keeps today's behavior.
    nonisolated static func slide(_ proxy: GeometryProxy,
                                  artworkHeight: CGFloat? = nil,
                                  cardTopReach: CGFloat = Theme.Size.heroPinnedRowTopPad) -> CGFloat {
        slideMeasurement(proxy, artworkHeight: artworkHeight, cardTopReach: cardTopReach) ?? 0
    }

    /// Optional-returning twin of `slide` (Wave 4 item 6, `docs/steven-batch-plan-2026-08-29.md`):
    /// `slide()` collapses "couldn't measure" (no enclosing scroll view resolved yet — e.g. mid a
    /// mixed-shape row's lazy relayout) and "measured, and the true slide is 0" into the same `0`
    /// return, which is correct for `slide()`'s two callers — the pre-seed draw-time branch (no
    /// prior state to hold, so 0 is the right default) and the probe (a blank measurement is
    /// already dropped by its own `guard`). It is NOT correct for `PinnedRowTitleTracking`'s
    /// `onGeometryChange`: that call site persists whatever it's handed into `@State`, so a
    /// transient nil read there un-parks a title that was correctly slid — a snap-then-flash the
    /// tester's scroll-right-then-up repro would see as the title jumping onto the clip edge and
    /// back. This variant lets that one caller tell the two cases apart and hold the previous
    /// value on nil instead of overwriting it with a false 0.
    /// The `captionVisible`/`rowIsFocused` defaults are deliberately not threaded here: `slide`
    /// depends on neither (it is `min(max(visible.minY, 0), cap)`), and those two only steer the
    /// belt's clearance choice. This wrapper's callers want the offset, nothing else.
    nonisolated static func slideMeasurement(_ proxy: GeometryProxy,
                                             artworkHeight: CGFloat? = nil,
                                             cardTopReach: CGFloat = Theme.Size.heroPinnedRowTopPad) -> CGFloat? {
        reading(proxy, artworkHeight: artworkHeight, cardTopReach: cardTopReach)?.slide
    }

    /// One title's tracked state: the eased slide, this row's static clearance, and the visibility
    /// belt's two hysteresis edges.
    ///
    /// Why the belt's condition is carried as two BOOLs rather than the raw `margin` they are
    /// derived from (load-bearing — `PinnedRowTitleTracking`'s cost note depends on it):
    /// `onGeometryChange` fires whenever its observed value CHANGES, and a row resting clear of the
    /// clip edge measures `slide == 0`, `hideCandidate == false`, `showAgain == true` at EVERY
    /// scroll position. Carrying `margin` itself would instead fire the observer once per frame for
    /// every visible row — exactly the per-frame churn the BUG-19/BUG-41 rule forbids. The settle
    /// re-reveal, which does need the raw numbers, measures the ROW instead
    /// (`pinnedRowSettleTracking`) and only while that row holds focus.
    // `nonisolated`: consumed inside `onGeometryChange`'s @Sendable transform — under the
    // project's default-MainActor isolation the synthesized Equatable conformance would
    // otherwise be actor-isolated and unable to satisfy the Sendable type parameter.
    nonisolated struct Reading: Equatable, Sendable {
        var slide: CGFloat
        /// This row's two clearances (`Clearances`), published onward to the settle re-reveal,
        /// which needs them to target artwork intrusion rather than raw margin but has only the
        /// ROW's frame to measure — the title's rendered height lives here. Constant for a given
        /// row and type size, so carrying them adds no `onGeometryChange` fires.
        var clearances: Clearances
        /// ARM edge of the belt's hysteresis: this title is in a state a viewer would call broken
        /// — clipped past the slide cap (`net < 0`), or riding more than `fadeIntrusionArm` onto
        /// the FOCUSED card's artwork — AND still on screen to be seen doing it.
        var hideCandidate: Bool
        /// RECOVER edge: fully inside the viewport AND clear of the focused card's artwork.
        /// Strictly stronger than `!hideCandidate`; the band between the two is where the belt
        /// holds whatever it has, so a rest sitting exactly at the corrected fixpoint
        /// (`liftedIntrusion == 0`) can never flicker.
        var showAgain: Bool
        /// How far the title's bottom currently sits past THIS row's artwork top, judged against
        /// the clearance its own cards are actually in (lifted while focused, at rest otherwise).
        /// Carried for the belt's probe lines; it is an affine function of `slide`, which is
        /// already here, so it adds no `onGeometryChange` fires of its own.
        var intrusion: CGFloat
        /// rc14 round 4 (verification workflow F3): `stillOnScreen` — whether the title's rendered
        /// band is still inside the viewport after sliding. The APPLIED slide is derived from
        /// this (off screen → 0) rather than from the sibling geometry observer's cache, so the
        /// seed and the gated apply no longer depend on the order SwiftUI runs the two observers'
        /// actions in. Flips once per edge crossing, so it adds no fires of its own.
        var onScreen: Bool = true
    }

    /// A `Reading` stamped with the tracking modifier's `remeasureTick` (Wave W5, BUG-87).
    ///
    /// Why the observer's value type is this and not `Reading` itself. `onGeometryChange` fires its
    /// action only when the transform's OUTPUT changes, and the two cases Wave W5 has to force a
    /// re-derivation in are exactly the two where the output does NOT change on its own:
    ///
    ///  - the FIRST-READING GRACE. A title that publishes its very first `Reading` off a layout
    ///    that is not final yet used to arm the belt on the spot; on an untouched cold-launch Home
    ///    nothing re-fires geometry afterwards, so the hide became permanent and only a relaunch
    ///    brought the title back — the tester's build-117 "the row title disappeared entirely"
    ///    (BUG-87). The grace defers the arm and bumps the tick 0.5s later; if the layout HAS
    ///    settled the fresh reading differs anyway, and if it has not, the tick is what still gets
    ///    the action to run so a genuinely broken title arms (0.5s late) rather than never.
    ///  - the RECOVERY WATCHDOG. A faded title only comes back through `showAgain`, which needs a
    ///    measurement. A title hidden on a stale layout produces none, so it stayed hidden forever.
    ///
    /// The tick is carried in the OBSERVER's value rather than in `Reading` so nothing downstream
    /// of `Reading` (`republishForModeChange`, `standDownFastPath`, `PinnedRowTitleProbe`,
    /// `noteClearances`) has to know it exists, and so `Reading`'s equality keeps meaning "the same
    /// measured geometry". A tick-only fire is byte-identical work to a no-op measurement: the
    /// slide does not change, `updateFade` finds `previous?.hideCandidate == true` and declines to
    /// re-arm, and `noteClearances` sees an unchanged value and returns.
    // `nonisolated`: same @Sendable-transform requirement as `Reading` above.
    nonisolated struct TickedReading: Equatable, Sendable {
        var tick: Int
        var reading: Reading
    }

    /// The two geometry inputs a `Reading` is computed from, cached by `PinnedRowTitleTracking` so
    /// a mode change can recompute one WITHOUT a new geometry pass (Codex r10 P2).
    // `nonisolated`: same @Sendable-transform requirement as `Reading` above.
    nonisolated struct TitleGeometry: Equatable, Sendable {
        /// The rows viewport's top edge in the title's own space — `+` means that much of the
        /// title is currently clipped away.
        var visibleMinY: CGFloat
        /// The title's own rendered height.
        var titleHeight: CGFloat
    }

    /// `slideMeasurement`'s full form. `nil` means "couldn't measure" (see `slideMeasurement`'s
    /// doc for why that must never be collapsed into a measured 0).
    nonisolated static func reading(_ proxy: GeometryProxy,
                                    artworkHeight: CGFloat? = nil,
                                    cardTopReach: CGFloat = Theme.Size.heroPinnedRowTopPad,
                                    captionVisible: Bool = true,
                                    rowIsFocused: Bool = false,
                                    treatment: RowCardTreatment = .cardTreatment,
                                    mode: FocusModeFlags = .current) -> Reading? {
        guard let visible = visibleBounds(proxy) else { return nil }
        return reading(geometry: TitleGeometry(visibleMinY: visible.minY,
                                               titleHeight: proxy.size.height),
                       artworkHeight: artworkHeight,
                       cardTopReach: cardTopReach,
                       captionVisible: captionVisible,
                       rowIsFocused: rowIsFocused,
                       treatment: treatment,
                       mode: mode)
    }

    /// The pure core, split out of the proxy form so the tracking modifier can re-derive a Reading
    /// from CACHED geometry when only the focus mode changed — a Settings toggle moves nothing, so
    /// there may be no next geometry pass to recompute in (Codex r10 P2).
    nonisolated static func reading(geometry: TitleGeometry,
                                    artworkHeight: CGFloat?,
                                    cardTopReach: CGFloat,
                                    captionVisible: Bool,
                                    rowIsFocused: Bool,
                                    treatment: RowCardTreatment,
                                    mode: FocusModeFlags) -> Reading {
        let visibleMinY = geometry.visibleMinY
        let titleHeight = geometry.titleHeight
        // The BINDING cap stays the absolute one (Codex 2026-08-29 P1): any cap below the rest's
        // real minY trades intrusion for CLIPPING — the title parks partially off-screen, the
        // original BUG-37 complaint class — and a settled rest deep enough to intrude is itself
        // the bug (a stale reveal after a mixed-shape row's lazy relayout; see the scroll-repro
        // trace in docs/steven-batch-plan-2026-08-29.md). Visibility wins; the proportional cap
        // below (`maxSlide`) stays PROBE-ONLY so device passes can read how far each rest
        // actually intruded per row and size until the settle-level fix removes the deep rests.
        let cap = maxSlideOverride ?? Theme.Size.heroPinnedRowTitleMaxSlide
        let slide = min(max(visibleMinY, 0), cap)
        // `net = margin + slide = −visibleMinY + slide`, so `overshoot = −net` and `net < 0` ⇔
        // the rest ate more than the cap can give back.
        let overshoot = visibleMinY - slide
        // Keeps the belt scoped to titles the viewer can still SEE: a row scrolled well above the
        // focused one is also past the cap (and saturated, so its intrusion reads as the full
        // 46pt), but it is simply scrolling away as designed (see this enum's header) and must not
        // arm anything. The title's own rendered band is `[slide, slide + height]` in local units,
        // so it is still on screen exactly while the viewport's top edge is above its bottom.
        let stillOnScreen = visibleMinY < titleHeight + slide
        let clearances = clearances(titleHeight: titleHeight,
                                    cardTopReach: cardTopReach,
                                    artworkHeight: artworkHeight,
                                    captionVisible: captionVisible,
                                    treatment: treatment,
                                    mode: mode)
        // Codex r2 P2-3: `net < 0` alone under-covers the belt. When the corrector is disarmed,
        // exhausted, or bottom-blocked, an INTRUSION-ONLY rest leaves a fully opaque title sitting
        // on the artwork — `net` is fine, the picture is not. The arm edge therefore takes either
        // failure.
        //
        // Codex r4 P1: and the intrusion is measured against the FOCUSED card
        // (`clearances.focused`), not the row's resting geometry. The title rides over the card
        // that has focus, which the focus treatment has raised, so the pre-lift number was
        // systematically optimistic — a belt that recovered at pre-lift zero would happily leave
        // the focused card's artwork under the title.
        //
        // Codex r7 P2: but ONLY the focused row's cards are raised. An unfocused row's artwork
        // sits at its resting top, so judging it by the lifted clearance invents an intrusion that
        // does not exist — an 11pt slide on an unfocused row would read as 5pt intruded when it is
        // actually 15pt CLEAR, and the belt could fade a title nothing was wrong with. Each row is
        // judged by the geometry its own cards are actually in.
        //
        // Hysteresis (arm above `fadeIntrusionArm`, recover only at `intrusion ≤ 0`) is what keeps
        // a rest parked exactly at the corrected fixpoint — where `slide == clearances.focused`,
        // i.e. intrusion 0 for the focused row — from sitting on the boundary and flickering.
        let effectiveClearance = rowIsFocused ? clearances.focused : clearances.atRest
        let intrusion = slide - effectiveClearance
        return Reading(slide: slide,
                       clearances: clearances,
                       hideCandidate: stillOnScreen && (overshoot > 1 || intrusion > fadeIntrusionArm),
                       showAgain: overshoot <= 0 && intrusion <= 0,
                       intrusion: intrusion,
                       onScreen: stillOnScreen)
    }

    /// How far the pinned hero must yield, in points, so the focused row FITS at the canonical
    /// rest for the current Poster Size (Wave 10).
    ///
    /// The structural problem this closes, device-verified: at Large the focused row needs the
    /// title band (`Spacing.lg` + `heroPinnedRowTopPad` = 112) plus 403pt of artwork below the
    /// pinned clip edge — ~515pt — and the pinned rows viewport is 455 in BOTH sim and device
    /// probes. Every rest was therefore forced to choose between cutting the poster's top and
    /// hiding the title; Waves 8/9 could only pick the least-bad option, never satisfy both. The
    /// hero yields exactly the shortfall and the choice disappears.
    ///
    /// STATIC, keyed to `PosterStyle` alone. It changes when the user changes Poster Size and at
    /// no other time — deliberately not per row, per focus, or per rest. A hero that resized as
    /// you moved between rows of different heights ("breathing") was the rejected design: it makes
    /// the clip edge a moving target, which is what the reveal regime is least able to cope with,
    /// and the tester's actual request was the opposite — rows landing in the SAME place every
    /// time.
    ///
    /// Small and Medium compute to exactly 0, so their layout is bit-identical to Wave 9 — see the
    /// arithmetic table on `Theme.Size.heroPinnedRowsSettledCushion`.
    ///
    /// `showsCTA` (2026-09-30) picks the viewport budget of the hero form on screen — the panel's is
    /// 38pt taller (`Theme.Size.heroPinnedRowsViewportBudget(showsCTA:)`). `PinnedRowGeometry.plan`
    /// deliberately calls this with `showsCTA: true` for its SCOPE GATE (which Poster Sizes enter
    /// the structural fit at all) and with the real form for its unsatisfiable fallback.
    nonisolated static func pinnedHeroCompression(rowArtworkHeight: CGFloat,
                                                  showsCTA: Bool) -> CGFloat {
        guard !heroCompressionDisabledByKnob else { return 0 }
        let requiredRowExtent = Theme.Spacing.lg
            + Theme.Size.heroPinnedRowTopPad
            + rowArtworkHeight
            + Theme.Size.heroPinnedRowsSettledCushion
        let raw = max(requiredRowExtent - Theme.Size.heroPinnedRowsViewportBudget(showsCTA: showsCTA), 0)
        let capped = min(raw, Theme.Size.heroPinnedCompressionCap)
        if raw > capped, cappedCompressionLogged != rowArtworkHeight {
            cappedCompressionLogged = rowArtworkHeight
            // Loud on purpose: past the cap the geometry is again unsatisfiable and the belt is
            // back in play, which is exactly the state a device pass needs to know it is looking at.
            NSLog("[HomeScrollProbe] hero %@",
                  "compression CAPPED want=\(Int(raw.rounded())) cap=\(Int(Theme.Size.heroPinnedCompressionCap))"
                    + " artwork=\(Int(rowArtworkHeight.rounded())) — rows still short, belt remains in play")
        }
        return capped
    }

    nonisolated(unsafe) private static var cappedCompressionLogged: CGFloat?

    /// `defaults write com.nuvio.media.NuvioTV debug.pinnedHeroCompressionOff -bool YES`, or as a
    /// launch argument on device/CI. Forces `pinnedHeroCompression` to 0 at every Poster Size,
    /// restoring the pre-Wave-10 geometry: the pinned rows viewport drops back to ~455 and a Large
    /// focused row no longer fits below the clip edge.
    ///
    /// It exists for ONE reason — to keep the visibility belt's gate honest. Wave 10 fixed the
    /// shortfall the belt was built for, which also deleted the belt's only reachable repro: with
    /// the compression in place the 2026-09-01 run measured `vh=524` and every down→up park settled
    /// healthy at `margin≈+22`, even with the corrector disarmed. A safety net whose failure mode
    /// has become unreachable is a safety net nobody can test, and it still has to work — for
    /// Poster Sizes past the compression cap, for mixed-shape extremes, and for whatever the next
    /// device geometry turns out to be. Turning the compression off reproduces the exact historical
    /// shortfall the belt was designed against, which makes test48 honest archaeology rather than a
    /// synthetic construction.
    ///
    /// Read once at launch like every other probe knob, and release-inert unless it is passed.
    nonisolated static let heroCompressionDisabledByKnob =
        UserDefaults.standard.bool(forKey: "debug.pinnedHeroCompressionOff")

    /// Verification for the constant `heroPinnedRowsViewportBudget` rests on: the live rows
    /// viewport should be exactly `budget + compression`. Logged once per distinct disagreement so
    /// a drifted platform metric shows up in a device log instead of silently mis-sizing the hero.
    nonisolated static func verifyViewportBudget(liveViewport: CGFloat, compression: CGFloat,
                                                 showsCTA: Bool) {
        guard HomeGeometryProbe.enabled else { return }
        // 2026-09-30: the budget depends on the hero form (the panel has no page-dots row).
        let budget = Theme.Size.heroPinnedRowsViewportBudget(showsCTA: showsCTA)
        let expected = budget + compression
        // Positive confirmation for device passes (FEAT-30 spike onward): one line per distinct
        // live viewport, so a log with no MISMATCH line is "matched", not "never measured".
        let liveKey = liveViewport.rounded()
        if viewportLiveLogged != liveKey {
            viewportLiveLogged = liveKey
            NSLog("[HomeScrollProbe] hero %@",
                  "viewport live=\(Int(liveKey)) expected=\(Int(expected.rounded()))")
        }
        guard abs(liveViewport - expected) > 4 else { return }
        let key = (liveViewport / 2).rounded()
        guard viewportBudgetMismatchLogged != key else { return }
        viewportBudgetMismatchLogged = key
        NSLog("[HomeScrollProbe] hero %@",
              "viewport BUDGET MISMATCH live=\(Int(liveViewport.rounded())) expected=\(Int(expected.rounded()))"
                + " (budget \(Int(budget)) + compression \(Int(compression.rounded())) showsCTA=\(showsCTA ? 1 : 0))")
    }

    nonisolated(unsafe) private static var viewportBudgetMismatchLogged: CGFloat?
    nonisolated(unsafe) private static var viewportLiveLogged: CGFloat?

    /// Arm threshold for the visibility belt's intrusion half — how far a title may ride onto its
    /// row's artwork (as that row's own cards are actually sitting: lifted if it holds focus, at
    /// rest otherwise) before "a missing title beats a title on the art" applies. Small, but above
    /// the rounding noise around the corrected fixpoint (intrusion 0), which is the rest the belt
    /// must never fire on.
    nonisolated static let fadeIntrusionArm: CGFloat = 4

    /// rc14: the slide a title actually APPLIES for a measured one — 0 when the title would be
    /// off screen even after sliding (`visibleMinY >= titleHeight + measured`, the complement of
    /// `reading`'s `stillOnScreen`), otherwise the measurement. Shared by the seed and the gated
    /// apply path so a recycled row re-mounting above the viewport cannot carry a stale 72 into
    /// its next Up approach. Pure, for the unit test.
    nonisolated static func appliedSlide(visibleMinY: CGFloat, titleHeight: CGFloat, measured: CGFloat) -> CGFloat {
        visibleMinY >= titleHeight + measured ? 0 : measured
    }

    /// The draw-time slide for the one frame before the first measurement lands (round 4, F3):
    /// the raw `slide(_:artworkHeight:cardTopReach:)` with the off-screen rule applied, so even
    /// that frame cannot paint a title 72pt down on a row that is entirely above the viewport.
    nonisolated static func preSeedSlide(_ proxy: GeometryProxy,
                                         artworkHeight: CGFloat?,
                                         cardTopReach: CGFloat) -> CGFloat {
        let raw = slide(proxy, artworkHeight: artworkHeight, cardTopReach: cardTopReach)
        guard let visible = visibleBounds(proxy) else { return raw }
        return appliedSlide(visibleMinY: visible.minY, titleHeight: proxy.size.height, measured: raw)
    }

    /// Signed clearance between the title's top and the viewport's top edge BEFORE sliding —
    /// negative means the rest fell short far enough to cut the title (BUG-37 reproducing).
    /// Probe-only.
    nonisolated static func rawMargin(_ proxy: GeometryProxy) -> CGFloat? {
        visibleBounds(proxy).map { -$0.minY }
    }
}

// ── beta.18 verdict (BUG-87/89, R1): the slide hold's verdict and clock ───────────────────────
//
// Pure and `nonisolated` so `PinnedRowSlideHoldTests` covers the exact logic
// `PinnedRowTitleTracking.commitSlide` runs, and the constants it times against.
extension PinnedRowTitle {
    nonisolated enum SlideHoldVerdict: Equatable, Sendable {
        /// Apply the target now (eased, or snapped under Reduce Motion).
        case apply
        /// Set the slide to 0 with no animation.
        case snapToZero
        /// Keep the target pending until the rest is decided (or the fallback fires).
        case hold
    }

    /// - A 0 target while the rows MOVE snaps (round 4 F2's "0 is never held", without the 0.22s
    ///   ease that let the title detach from a row still travelling); at rest it eases as before.
    /// - A nonzero target waits while the rows move OR a settle decision is still to come: the
    ///   decision may be a nudge, and a title applied before it eases a second time after it.
    nonisolated static func slideHoldVerdict(target: CGFloat, current: CGFloat,
                                             moving: Bool, restPending: Bool) -> SlideHoldVerdict {
        if target == 0 {
            return (moving && current != 0) ? .snapToZero : .apply
        }
        return (moving || restPending) ? .hold : .apply
    }

    /// rc14: "moving" = the rows scroll's own stamp or this title's frame changed inside this
    /// window. beta.18 verdict (BUG-87/89, R1): no longer the release clock — the per-row settle
    /// decision (`PinnedRowSettle.observeRestDecision`) is the primary release, and this is only the
    /// motion test and the FALLBACK chain's re-check cadence.
    nonisolated static let slideMotionHold: TimeInterval = 0.12
    /// beta.18 verdict (BUG-87/89, R1): wall-clock fallback for a hold still waiting on a decision.
    /// Longer than `settleDelay + nudgeDuration` (0.5s) so a decision that comes always wins.
    nonisolated static let slideHoldMax: TimeInterval = 0.6
    /// beta.18 verdict (BUG-87/89, R1): hard ceiling per hold EPISODE, from its first hold. Past it
    /// the pending target applies whatever the rows are doing — a title is never held forever.
    /// review r1 (P3-5): the FIRST ceiling applies only if the rows are still; if they are still
    /// moving the episode clock restarts once (`ceilingRestarted`), and the SECOND ceiling applies
    /// regardless. So the worst-case hold is ≈ 2 x this value (plus up to two re-check ticks).
    nonisolated static let slideHoldCeiling: TimeInterval = 1.5
}

/// Swift-side navigation value. Kotlin data classes don't conform to Swift `Hashable`, so we wrap the
/// `MetaPreview` and hash on its stable identity (type + id) while still carrying all its fields for
/// the destination's initial render. Shared by Home, Search, and detail "more like this".
struct TitleRoute: Hashable {
    let preview: MetaPreview

    static func == (lhs: TitleRoute, rhs: TitleRoute) -> Bool {
        lhs.preview.id == rhs.preview.id && lhs.preview.type == rhs.preview.type
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(preview.id)
        hasher.combine(preview.type)
    }
}

/// Navigation value for the full-grid "See All" screen. `CatalogTarget` is a Kotlin sealed interface
/// and can't be a `NavigationStack` value directly, so we wrap it — hashing on the section's stable
/// `key` while carrying the title + target for the destination (same approach as `TitleRoute`).
struct CatalogRoute: Hashable {
    let key: String
    let title: String
    let target: any CatalogTarget

    init(section: HomeCatalogSection) {
        self.key = section.key
        self.title = section.title
        self.target = section.target
    }

    static func == (lhs: CatalogRoute, rhs: CatalogRoute) -> Bool { lhs.key == rhs.key }

    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// Navigation value for a cast/crew member's detail page (TMDB person id + name for the initial
/// render). Only produced when a `MetaPerson` has a `tmdbId`. Hashes on the id.
struct PersonRoute: Hashable {
    let id: Int
    let name: String

    static func == (lhs: PersonRoute, rhs: PersonRoute) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Navigation value for a studio/network browse page (TMDB discover-by-company/network). Only
/// produced when a `MetaCompany` has a `tmdbId`. `isNetwork` picks the TMDB entity kind (networks
/// come from `meta.networks`, studios from `meta.productionCompanies`); `sourceType` is the origin
/// title's type ("movie"/"series"), which orders the rails. Hashes on kind + id.
struct EntityRoute: Hashable {
    let id: Int
    let name: String
    let isNetwork: Bool
    let sourceType: String

    static func == (lhs: EntityRoute, rhs: EntityRoute) -> Bool {
        lhs.id == rhs.id && lhs.isNetwork == rhs.isNetwork
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isNetwork)
    }
}

/// A single poster tile, now backed by the shared `PosterCard` design-system component
/// (cached artwork, shimmer, brand focus ring, focus-aware title).
struct PosterCardView: View {
    let item: MetaPreview
    /// See `PosterCard.footnote`.
    var footnote: String? = nil
    /// FEAT-64: see `PosterCard.watchBadge` (catalog rows pass it through `InlineTrailerCard`).
    var watchBadge: PosterWatchBadge? = nil

    var body: some View {
        PosterCard(title: item.name, imageURL: item.poster, fallbackImageURL: item.rawPosterUrl,
                   watchBadge: watchBadge, footnote: footnote)
    }
}

