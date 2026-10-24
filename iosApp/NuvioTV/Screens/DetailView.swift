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

