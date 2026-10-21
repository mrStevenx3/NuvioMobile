import Foundation

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
    static let heroFade = 0.25
}
