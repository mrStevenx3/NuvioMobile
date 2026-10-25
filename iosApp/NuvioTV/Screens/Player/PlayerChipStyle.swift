import SwiftUI

// One look for every transient player affordance ("Skip Intro/Outro/Recap", "Play Next Episode",
// the up-next countdown) on BOTH engines. On the native AVPlayer screen the interactive chips are
// AVPlayerViewController.contextualActions (Apple's own affordance — focusable glass pill, system
// position); the mpv screen can't host focusable UI (libmpv owns the remote), so it draws
// `PlayerActionChip` in the same spot with the same label/symbol and triggers on D-pad Down. The
// countdown/status caption is app-drawn on both engines (`PlayerChipCaption`) because a UIAction
// title that changes every second re-animates the whole transport bar.
enum PlayerChipStyle {
    static let animation: Animation = .easeInOut(duration: 0.25)
    /// Bottom-trailing inset from the screen edge (overscan-safe), both engines.
    static let edgePadding: CGFloat = Theme.Spacing.screen
    /// Chip insets while the mpv transport bar is up: clear of the pill row (top at 213 from the
    /// bottom) and aligned with the track end.
    static let barUpBottomInset: CGFloat = 240
    static let barUpTrailingInset: CGFloat = 86
    /// While a swipe scrub's preview card is up: above the card's chapter label (top at 681 on a
    /// 1080 canvas, 1080 − 681 + 21).
    static let scrubCardBottomInset: CGFloat = 420
    /// SF Symbols mirrored on the native contextual actions.
    static let skipSymbol = "forward.frame.fill"
    static let nextSymbol = "forward.end.fill"
    // A prompt is an action, not a selection, so it never wears the brand accent
    // (docs/design/hig-hybrid-contract.md). BUG-180: the chips draw `PlayerSurfaceStyle`, not glass.
    /// Skip window ends this many seconds before the segment end so the affordance disappears
    /// cleanly (both engines' `updateSkipPrompt`).
    static let lastSecondExclusion: Double = 1
}

extension NextEpisodeEngine.Phase {
    /// Caption text for the up-next phase (nil = no caption). Shared by both engines.
    func chipCaption(nextTitle: String) -> (text: String, symbol: String?, progress: Bool)? {
        switch self {
        case .hidden: return nil
        case .searching: return (String(localized: "Finding next episode…"), nil, true)
        case .counting(let seconds):
            let title = nextTitle.count > 40 ? String(nextTitle.prefix(38)) + "…" : nextTitle
            return (String(localized: "Up next · \(title) · playing in \(seconds)s"), "forward.end", false)
        case .stillWatching: return (String(localized: "Still watching?"), "questionmark.circle", false)
        case .noStream: return (String(localized: "No stream found for the next episode."), "exclamationmark.circle", false)
        }
    }
}
