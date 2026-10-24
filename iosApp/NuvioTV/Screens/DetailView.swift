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

