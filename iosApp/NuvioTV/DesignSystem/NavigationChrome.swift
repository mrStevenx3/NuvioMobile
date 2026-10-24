import Foundation
import UIKit   // UIFocusHeading only

// Home Stage & Strip (H9, FEAT-45; P4 spec §1.1): the navigation chrome's pure half. Everything in
// this file is a value or a function of values, unit-tested by `NavigationChromeTests` and
// `RailFocusPolicyTests`. The view (`NavigationRail`), its model and the shell wiring live in
// `NavigationRail.swift`.

// MARK: - Mode, visibility, migration, inset math

/// Which navigation chrome the tab shell shows: the system's top tab bar (Tabs, the default) or the
/// floating pill rail on the left (Rail). Rail replaced FEAT-30's Menu-revealed Sidebar mode.
///
/// Both keys are DEVICE-LOCAL `UserDefaults` strings, never synced (no reference in `shared/` or in
/// any sync blob): which chrome a living-room TV shows is a per-device display preference.
///
/// EVERY read of the mode must resolve to Tabs on an untouched install, and everything the rail adds
/// is structurally absent then: the call sites branch `if NavigationChrome.isRail() { … } else
/// { content }` rather than passing an inert value into an always-applied modifier, so Tabs mode
/// stays byte-identical. Reads are live (a `UserDefaults` lookup), never launch-latched: the mode
/// changes only across `ContentView`'s `.id(theme|style|visibility|font)` remount, and a remount
/// re-creates views, not type storage, so a latched `static let` would leave the shell half switched.
nonisolated enum NavigationChrome {
    /// Kept from FEAT-30 so the stored choice survives the rename.
    static let styleKey = "sidebar_style"
    /// New with the rail: Always Visible / Hide While Browsing / Hidden (FEAT-62).
    static let railVisibilityKey = "rail_visibility"
    /// FEAT-80 (Steven rc7): where the pill sits on the left edge, and whether it shows labels.
    /// Device-local like the two keys above.
    static let railPositionKey = "rail_position"
    static let railLabelsKey = "rail_labels"
    /// Batch P (P2, Steven rc10 photo 1): Floating (the default pill, `bezelInset` off the edge) or
    /// Edge (flat against the left screen edge, square outer corners). Device-local like the keys
    /// above. Never changes the reserved width, so it needs no remount.
    static let railStyleKey = "rail_style"
    /// FEAT-30's stored value. Reads as Rail, and `migrateLegacy` rewrites it once.
    static let legacySidebarValue = "sidebar"

    enum Style: String, Equatable, Sendable {
        case tabs
        case rail
        /// Steven's fork: the Orbit top bar (`OrbitTopBar`), the default when nothing is stored.
        case orbit
    }

    enum RailVisibility: String, Equatable, Sendable {
        case always
        case whileBrowsing = "browsing"
        /// FEAT-62 (Steven, beta.19-rc3 follow-up 2026-10-08: "hide it on the first line, show it on
        /// Left/Back"): the rail is off screen at rest everywhere, Home's row 0 included, and only a
        /// reveal shows it (Left from the first card, through the failed-move arm, or Menu). It hides
        /// again as soon as focus leaves it. Reserves no width, like Hide While Browsing.
        case hidden
    }

    /// FEAT-80: Centre (the default, the pill vertically centred on the left edge) or Corner
    /// (Batch N; redesigned in Batch O, Christian's 2026-10-20 mock): a bare Home icon at the
    /// top-left that unrolls into the Centre pill, anchored at the top, when the rail opens.
    /// Corner replaced rc8's Top, which still reads as Corner (`railPosition(raw:)`), so no stored
    /// value needs a write.
    enum RailPosition: String, Equatable, Sendable, CaseIterable {
        case centre
        case corner
    }

    /// rc8's stored Top value. Resolves to Corner.
    static let legacyTopPositionValue = "top"

    /// FEAT-80: Shown (the default; the pill grows to show labels when it opens) or Icons Only (the
    /// pill keeps its collapsed width and never draws labels).
    enum RailLabels: String, Equatable, Sendable, CaseIterable {
        case shown
        case iconsOnly = "icons"
    }

    /// Batch P (P2): Floating (the default) or Edge (flush with the screen's left edge).
    enum RailStyle: String, Equatable, Sendable, CaseIterable {
        case floating
        case edge
    }

    /// Only "edge" is Edge (trimmed, case-insensitive); anything else keeps today's Floating pill.
    static func railStyle(raw: String?) -> RailStyle {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == RailStyle.edge.rawValue ? .edge : .floating
    }

    /// The pill's leading edge from the screen edge: `bezelInset` Floating, 0 Edge. `reservedEdge`
    /// and `pillTrailingEdge` deliberately do NOT derive from it (Edge must not move content).
    static func pillLeading(_ style: RailStyle) -> CGFloat {
        style == .edge ? 0 : bezelInset
    }

    /// "corner", and rc8's "top", read as Corner (FEAT-80, Batch N); anything else (missing,
    /// "centre", unknown) is Centre, so an untouched install keeps today's rail.
    static func railPosition(raw: String?) -> RailPosition {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case RailPosition.corner.rawValue?, legacyTopPositionValue?: return .corner
        default: return .centre
        }
    }

    static func railPosition(_ defaults: UserDefaults = .standard) -> RailPosition {
        railPosition(raw: defaults.string(forKey: railPositionKey))
    }

    /// Anything but "icons" is Shown, so a missing or unknown value keeps today's rail.
    static func railLabels(raw: String?) -> RailLabels {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == RailLabels.iconsOnly.rawValue ? .iconsOnly : .shown
    }

    /// FEAT-80 Corner (Batch O): the tvOS top safe-area line on a 1920 × 1080 canvas. The Home
    /// cell lands on it, at rest (the bare glyph) and open (the pill's first row).
    static let cornerSafeTop: CGFloat = 60
    /// The open pill's top edge (38): `cornerSafeTop` less the pill's `verticalPadding`, so the
    /// Home cell sits on the safe-area line. The glass's top edge sits above the vertical safe
    /// area, as Centre's pill already sits outside the horizontal one. Leading, the pill keeps
    /// Centre's `bezelInset`.
    static let cornerPillTop: CGFloat = cornerSafeTop - verticalPadding

    // MARK: Layout numbers the math needs (mirrors of `RailMetrics`, NavigationRail.swift)

    /// The pill's leading edge from the screen edge (P4 R3; kept for this beta, critique Q6).
    static let bezelInset: CGFloat = 16
    /// The collapsed pill's width.
    static let collapsedWidth: CGFloat = 84
    /// The pill's padding above its first item and below the profile avatar (FEAT-80 Corner's
    /// `cornerPillTop` is derived from it).
    static let verticalPadding: CGFloat = 22
    /// The gap the rail keeps from content when it reserves width.
    static let contentGap: CGFloat = 16
    /// `bezelInset + collapsedWidth + contentGap`: what Always Visible reserves from the bezel.
    static let reservedEdge: CGFloat = bezelInset + collapsedWidth + contentGap
    /// The collapsed pill's trailing edge (x = 100 on a 1920 canvas).
    static let pillTrailingEdge: CGFloat = bezelInset + collapsedWidth
    /// The widest focus lift a row card draws past its leading edge: a 500 pt Saga card under the
    /// measured system lift (≈1.1212, `PosterCard.swift`) grows ≈30 pt per side. The clearance test
    /// checks that a lifted first card never reaches under the pill in either visibility.
    static let widestRowLiftOverhang: CGFloat = 30

    // MARK: Resolution

    /// "rail", and FEAT-30's "sidebar", read as Rail; anything else (missing, "tabs", a corrupted
    /// or future string) is Tabs, never an unknown third state. Trimmed and lower-cased so a
    /// hand-typed launch argument (`-sidebar_style Rail`) still resolves.
    static func style(raw: String?) -> Style {
        // Steven's fork: an untouched install gets the Orbit bar.
        guard let raw else { return .orbit }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case Style.rail.rawValue, legacySidebarValue: return .rail
        case Style.orbit.rawValue: return .orbit
        default: return .tabs
        }
    }

    static func style(_ defaults: UserDefaults = .standard) -> Style {
        style(raw: defaults.string(forKey: styleKey))
    }

    /// Steven's fork (2026-10-24): Orbit is the only navigation — Chris's rail and the system tab
    /// bar are gone, whatever an old install stored.
    static func isRail(_ defaults: UserDefaults = .standard) -> Bool { false }

    /// Steven's fork: the Orbit top bar replaces the system tab bar (hidden) and the rail.
    static func isOrbitBar(_ defaults: UserDefaults = .standard) -> Bool { true }

    /// "browsing" reads as Hide While Browsing, "hidden" as Hidden (FEAT-62); anything else is
    /// Always Visible (the default).
    static func railVisibility(raw: String?) -> RailVisibility {
        guard let raw else { return .always }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case RailVisibility.whileBrowsing.rawValue: return .whileBrowsing
        case RailVisibility.hidden.rawValue: return .hidden
        default: return .always
        }
    }

    static func railVisibility(_ defaults: UserDefaults = .standard) -> RailVisibility {
        railVisibility(raw: defaults.string(forKey: railVisibilityKey))
    }

    /// Rail mode with the rail Always Visible in Centre: the only configuration that moves content.
    /// FEAT-80: Corner reserves nothing, as at rest it is only the Home icon in the corner (the
    /// device pass checks that no page's top-left header sits under it).
    static func reservesWidth(_ defaults: UserDefaults = .standard) -> Bool {
        false
    }

    /// The pure half of `reservesWidth(_:)`, Rail mode assumed.
    static func reservesWidth(visibility: RailVisibility, position: RailPosition) -> Bool {
        visibility == .always && position == .centre
    }

    // MARK: Migration (P4 R6, §4.2)

    /// What a PERSISTED `sidebar_style` value migrates to: "rail" for exactly FEAT-30's "sidebar",
    /// nil (leave it alone) for everything else, including a missing key and "rail" itself.
    static func migratedValue(forPersisted raw: Any?) -> String? {
        guard let value = raw as? String, value == legacySidebarValue else { return nil }
        return Style.rail.rawValue
    }

    /// Once per launch from `NuvioTVApp.init`, before any view reads the mode. Reads the PERSISTENT
    /// domain only (`persistentDomain(forName: domain)`), so a `-sidebar_style sidebar` launch
    /// argument, which lives in the argument domain, is never written to disk. Idempotent: it writes
    /// only while the stored value is exactly "sidebar", so a second run is a no-op. Never touches
    /// `rail_visibility`, which an untouched install leaves unset (Always Visible). Returns whether
    /// it wrote.
    @discardableResult
    static func migrateLegacy(_ defaults: UserDefaults, domain: String) -> Bool {
        guard !domain.isEmpty,
              let migrated = migratedValue(forPersisted: defaults.persistentDomain(forName: domain)?[styleKey])
        else { return false }
        defaults.set(migrated, forKey: styleKey)
        NSLog("[NavRail] migrated %@ \"%@\" to \"%@\" (device-local, once)", styleKey, legacySidebarValue, migrated)
        return true
    }

    // MARK: Inset math (P4 R3, §5.1)

    /// How much leading safe area an Always Visible rail adds to every tab root: the reserved edge
    /// beyond the side safe area the content already keeps (116 − 80 = 36 on a 1080p canvas). Never
    /// negative, and 0 when the rail does not reserve width or (FEAT-80) sits in the Corner.
    static func contentSafeAreaExtra(sideSafeArea: CGFloat, reservesWidth: Bool, position: RailPosition) -> CGFloat {
        guard reservesWidth, position == .centre else { return 0 }
        return max(0, reservedEdge - sideSafeArea)
    }

    /// Where a tab root's content starts from the bezel: the side safe area, the rail's extra, then
    /// the 60 pt content margin (`Theme.Spacing.screen`). 176 Always Visible in Centre, 140 otherwise.
    static func contentLeading(sideSafeArea: CGFloat, reservesWidth: Bool, position: RailPosition) -> CGFloat {
        sideSafeArea + contentSafeAreaExtra(sideSafeArea: sideSafeArea, reservesWidth: reservesWidth, position: position)
            + Theme.Spacing.screen
    }

    /// The rows' distance to the visible screen edges (`\.rowEdgeMargins`), the rail's edge counting
    /// as the leading one: (176, 140) Always Visible in Centre, (140, 140) otherwise (Corner included,
    /// FEAT-80). Computed from the passed side safe area, so production (which passes
    /// `PinnedRowGeometry.sideSafeArea`) gets exactly `RowEdgeMargins.standard` when the rail
    /// reserves nothing.
    static func rowEdgeMargins(sideSafeArea: CGFloat, reservesWidth: Bool, position: RailPosition) -> RowEdgeMargins {
        let margin = Theme.Spacing.screen + sideSafeArea
        return RowEdgeMargins(
            leading: margin + contentSafeAreaExtra(sideSafeArea: sideSafeArea, reservesWidth: reservesWidth,
                                                   position: position),
            trailing: margin
        )
    }

    /// See `Theme.Size.sidebarTopCompensation` (still ships 0, so `.railTopCompensation()` applies
    /// nothing). Main-actor: the constant lives with the pinned-hero budget in `Theme.Size`.
    @MainActor
    static var topCompensation: CGFloat { Theme.Size.sidebarTopCompensation }
}

