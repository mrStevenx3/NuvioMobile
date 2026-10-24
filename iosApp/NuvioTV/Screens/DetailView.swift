import SwiftUI
import SharedCore

// Steven's fork (2026-10-24): Chris's detail page is gone (the Orbit page, OrbitDetailView.swift,
// is the only one). What stays here is shared by other screens.

/// rc14 (Steven rc13 verdict, 2026-09-30): the Detail backdrop was reported softer than the
/// reference app's. The addon/TMDB URL the meta carries is the *medium* rendition, so Detail asks
/// for the larger one first and falls back to the original URL when the larger file does not exist
/// (`CachedAsyncImage(string:fallback:)` retries the fallback once the primary fails).
///
/// Pure string rewrite, `nonisolated` so a unit test can call it synchronously from any isolation
/// domain. Only two well-known path shapes are rewritten; every other URL passes through untouched.
enum DetailBackdropURL {
    /// metahub `/background/medium/…` -> `/background/large/…`; TMDB `/t/p/w1280/…` ->
    /// `/t/p/original/…`. Anything else (including an empty string) is returned unchanged.
    nonisolated static func upgraded(_ url: String) -> String {
        if url.contains("/background/medium/") {
            return url.replacingOccurrences(of: "/background/medium/", with: "/background/large/")
        }
        if url.contains("/t/p/w1280/") {
            return url.replacingOccurrences(of: "/t/p/w1280/", with: "/t/p/original/")
        }
        return url
    }
}


/// Batch M Wave 0 (BUG-153 regressed in rc9): launch-latched A/B knobs, one per rc7 → rc9 suspect,
/// set per run with launch arguments (`-debug.detailImmediateTrailerMount YES`, …) and compared
/// under `debug.detailScrollProbe`.
enum DetailBug153Knobs {
    /// Restores rc7's immediate trailer mount (Batch K deferred it until the scroll settles).
    static let immediateTrailerMount = UserDefaults.standard.bool(forKey: "debug.detailImmediateTrailerMount")
    /// Skips the FEAT-60 compact logo overlay (Batch C).
    static let noCompactLogo = UserDefaults.standard.bool(forKey: "debug.detailNoCompactLogo")
    /// Puts Trailers, Episodes and Season tiles back on `TileFocusLift` (BUG-177's ring path off).
    static let noTileRing = UserDefaults.standard.bool(forKey: "debug.detailNoTileRing")
    /// Batch M Wave 1: keeps the tile ring but drops the focused tile's black platter + 22 pt
    /// shadow (`CardArtworkFocusLift.focusShadow`), the main suspect under the SwiftUI scale.
    static let ringNoShadow = UserDefaults.standard.bool(forKey: "debug.detailTileRingNoShadow")
    /// Batch M Wave 1: keeps the tile ring but snaps it: no animation on the ring branch's lift,
    /// ring and band (`DetailTileFocusLift`), nor on the tile's own `value: isFocused` animation.
    static let ringNoAnim = UserDefaults.standard.bool(forKey: "debug.detailTileRingNoAnim")
}


/// Circular cast avatar + name/role. Platter-free: used inside a `.poster`-styled NavigationLink
/// when tappable, so it supplies its own focus visuals (ring + scale + shadow); rendered bare for
/// non-tappable cast, where `isFocused` simply never fires.
struct CastCard: View {
    let person: MetaPerson
    /// Caller-supplied focus truth for the no-zoom still ring (Codex 2026-08-29 rounds 3-5):
    /// with the system focus effect disabled this card's only treatment was caption opacity, and
    /// the generic outer-bounds ring wrapped the whole lockup — the ring belongs on the avatar
    /// circle, whose geometry only this view knows.
    var stillFocused: Bool = false

    @AppStorage("no_zoom_on_focus") private var noZoomOnFocus = false
    /// BUG-102 (rc9): same gap as `FolderTile` — the avatar only knew the no-zoom still ring, so
    /// with zoom on and the accent ring on it drew nothing. Resolved through `PlainLabelRing`.
    @AppStorage("accent_focus_ring") private var accentFocusRing = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reservesRingBand: Bool {
        PlainLabelRing.reservesBand(accentFocusRing: accentFocusRing, noZoomOnFocus: noZoomOnFocus)
    }

    /// BUG-108: same architecture as `FolderTile` — ring mode takes the native `.borderless` lift
    /// away from this label, so the avatar lifts itself and carries its ring up with it.
    private var artworkLift: CardFocusMode {
        PlainLabelRing.lift(accentFocusRing: accentFocusRing, noZoomOnFocus: noZoomOnFocus)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // BUG-41: CachedAsyncImage over the raw AsyncImage (cast rows re-decoded every photo on
            // every scroll-triggered re-render before this). `person.photo` empty/nil is guarded
            // outside the image (matching the old `URL(string: "")` == nil no-fetch behavior) so the
            // person glyph appears immediately rather than after a load attempt.
            Group {
                if let photo = person.photo, !photo.isEmpty {
                    CachedAsyncImage(string: photo, contentMode: .fill, failure: { CastCard.personFallback })
                } else {
                    CastCard.personFallback
                }
            }
            .frame(width: Theme.Size.castAvatar, height: Theme.Size.castAvatar)
            .clipShape(Circle())
            .nuvioCardDepth(Circle(), surface: .cast)
            // 2026-08-30 no-zoom investigation: same overpaint/fix as TileFocusLift/FolderTile —
            // the ring used to strokeBorder straight over the avatar's own true edge. Static,
            // never-focus-linked shrink (matches `ringInset`'s "always reserved, never pops"
            // contract) so the `.overlay` below measures the avatar's TRUE, unscaled bounds. A
            // single scalar is enough — the avatar is always a perfect circle/square.
            // BUG-102: band reserved whenever a ring may draw (`ringInset`'s rule), as FolderTile.
            .scaleEffect(reservesRingBand && Theme.Size.castAvatar > 0
                ? max(0, Theme.Size.castAvatar - 2 * ringWidth) / Theme.Size.castAvatar
                : 1)
            .overlay {
                if let ring = PlainLabelRing.resolve(accentFocusRing: accentFocusRing,
                                                     noZoomOnFocus: noZoomOnFocus,
                                                     focused: stillFocused) {
                    Circle().strokeBorder(ring.color, lineWidth: ringWidth)
                }
            }
            .modifier(CardArtworkFocusLift(
                mode: artworkLift,
                isFocused: stillFocused,
                artworkHeight: Theme.Size.castAvatar,
                // `CardArtworkFocusLift.manualScale` draws its platter as a
                // `RoundedRectangle(cornerRadius:)` at the attached view's bounds. The bounds here
                // are the avatar's 140×140 square, and a rounded rect of half that side IS that
                // square's inscribed circle — so the platter and its shadow follow the photo's own
                // edge instead of a square behind it. Derived from the constant, never literal 70.
                cornerRadius: Theme.Size.castAvatar / 2
            ))
            VStack(spacing: Theme.Spacing.xs) {
                Text(person.name)
                    .font(Theme.Font.caption)
                    .foregroundStyle(isFocused ? Theme.Palette.textPrimary : Theme.Palette.textPrimary.opacity(0.9))
                    .lineLimit(1)
                    .frame(width: Theme.Size.castAvatar + 10)
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .frame(width: Theme.Size.castAvatar + 10)
                }
            }
            // BUG-108: the avatar grows downward by the same 20pt it rises, so name+role follow it
            // together — one modifier on the pair, so the two lines can never drift apart. 0 in
            // both other modes.
            .modifier(CardCaptionFocusDrop(mode: artworkLift, isFocused: stillFocused,
                                           artworkHeight: Theme.Size.castAvatar))
        }
        // BUG-108: gated on Reduce Motion now that this wraps a manual `.scaleEffect` — see
        // `CardArtworkFocusLift`, which passes a nil animation there and would be overridden here.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
    }

    /// BUG-41 failure/no-photo fallback — pulled out of `body` so both the "no `person.photo`"
    /// branch and `CachedAsyncImage`'s `failure:` builder render the identical glyph.
    @ViewBuilder
    static var personFallback: some View {
        ZStack {
            Theme.Palette.surface
            Image(systemName: "person.fill")
                .font(Theme.Font.screenTitle)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
