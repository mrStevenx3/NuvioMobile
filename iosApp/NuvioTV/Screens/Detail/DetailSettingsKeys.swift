import Foundation
import SwiftUI

/// FEAT-35 (Detail revamp, 2026-10-02): the device-local `@AppStorage` keys behind the Detail
/// page's layout picker, its section toggles and the spoiler setting. Device-local on purpose, like
/// the older `detail_*` keys: the phone's Detail choices never reshape the TV (plan, "Storage").
///
/// These literals are canonical (plan OUTCOME, Wave 0): the Settings → Detail Page pane binds to
/// these constants, never to its own copies.
nonisolated enum DetailSettingsKeys {
    /// `DetailLayout.rawValue`; unknown or missing → `.cinematic` (D2).
    static let layout = "detail_layout"
    static let sectionStudioLogos = "detail_section_studio_logos"
    static let sectionParentalGuide = "detail_section_parental_guide"
    static let sectionRatings = "detail_section_ratings"
    static let sectionCast = "detail_section_cast"
    static let sectionCollection = "detail_section_collection"
    static let sectionTrailers = "detail_section_trailers"
    static let sectionMoreLikeThis = "detail_section_more_like_this"
    static let sectionComments = "detail_section_comments"
    static let sectionAbout = "detail_section_about"
    /// Must equal `EpisodeSpoilerRules.defaultsKey` (pinned by `EpisodeSpoilerRulesTests`).
    static let hideEpisodeSpoilers = "detail_hide_episode_spoilers"
}

/// D2: Cinematic is the default; Classic keeps today's page for one or two betas, then goes.
nonisolated enum DetailLayout: String, CaseIterable {
    case cinematic
    case classic

    /// Anything that is not a known raw value (an empty string, a typo from a launch argument)
    /// resolves to the default rather than to a blank page.
    static func resolve(_ raw: String) -> DetailLayout {
        DetailLayout(rawValue: raw) ?? .cinematic
    }
}

/// Steven's fork: the "Apple TV style" variant of the Cinematic Detail page (Settings → Detail
/// Page, on by default). Four changes, all Cinematic-only:
///  - the synopsis sits beside the action row, two lines, with a chevron that opens the full text;
///  - the bottom of the backdrop is frosted (a material faded in from the hero's lower half);
///  - leaving the hero frosts the whole backdrop (lighter dim, so it reads as glass, not black)
///    and fades the hero text out;
///  - the compact title logo shows on the first Down, above the first row, and rides up with that
///    row once the page scrolls further, instead of staying pinned for the whole page.
nonisolated enum DetailAppleStyle {
    static let defaultsKey = "detail_apple_style"
    static let synopsisLines = 2
    /// The visible dim is scaled by this while frosted (the dim MODEL is unchanged, so the
    /// trailer's tear-down latch still fires at the same scroll depth).
    static let dimScale: Double = 0.75
    /// Where the bottom frost starts, as a fraction of the screen height from the top.
    static let bottomFrostStart: CGFloat = 0.55
    /// The frost reaches full strength once the dim reaches this.
    static let fullFrostDim: Double = 0.35
    static let heroFade = 0.4
    /// The hero fills the screen in this style (no peek of the first row); its content keeps this
    /// gap to the bottom edge, so the buttons and the credits sit at the very bottom.
    static let heroBottomInset: CGFloat = 50
    /// Device pass 3: a larger compact logo, and the rows rest lower to leave it room.
    static let logoSlotHeight: CGFloat = 130
    static let logoMaxWidth: CGFloat = 640
    static let logoTop: CGFloat = 40
    /// Where a focused row's top rests in this style (Classic Cinematic: 108).
    static let rowRest: CGFloat = 196
    /// The compact logo fades in once the hero text has mostly faded (device pass 2: the two
    /// overlapped on the first Down).
    static let logoFadeDelay = 0.25
    static let logoFade = 0.35
    static let unfoldAnimation = Animation.easeInOut(duration: 0.35)
    /// UIKit's focus engine skips views at opacity 0, so the faded hero stays at this (invisible)
    /// opacity and Up can still reach it (device pass 2: Up never came back to the hero).
    static let hiddenButFocusable = 0.011
}
