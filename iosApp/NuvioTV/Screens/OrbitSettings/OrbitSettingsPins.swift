import Foundation
import SharedCore

// Orbit Réglages (Steven, 2026-10-24): the settings that left with Chris's screens are pinned to
// Orbit's choices, so no hidden value can still change the app.
//
// - Every launch: the Orbit bar and Orbit's home stay on (their switches are gone).
// - Once:
//   - Chris's test switches and probes ("debug.…" keys: A/B legs, diagnostics) go back to their
//     normal values;
//   - every look setting that left (theme, focus ring, card depth, posters, font, navigation,
//     home and detail layouts, detail sections, trailer placement, player extras) goes back to
//     its default, Orbit's one look;
//   - the custom poster service (RPDB…) is cleared.
//   Kept: what the new settings still offer (previews, spoilers, default player…).
enum OrbitSettingsPins {
    private static let onceKey = "orbit.settingsPins.v2"
    /// The crash guard of the seek preview harvester is not a test switch: it stays.
    private static let keptDebugKeys: Set<String> = [HarvestCrashSentinel.disabledKey]

    /// Look settings stored on this Apple TV: removed, so each falls back to its default.
    private static let lookKeys: [String] = [
        // Appearance
        "hero_poster_focus_only", "settings_style", "accent_focus_ring", "focus_ring_poster_color",
        "depth_rail_poster_color", "no_zoom_on_focus",
        RowEdgeFadeSetting.defaultsKey, HeadingDetailsSetting.defaultsKey, Theme.AppFontFamily.defaultsKey,
        NavigationChrome.railVisibilityKey, NavigationChrome.railPositionKey,
        NavigationChrome.railLabelsKey, NavigationChrome.railStyleKey,
        // Home screen
        FolderLayoutDefault.defaultsKey, FolderLayoutDefault.classicDefaultsKey, AmbientWashSetting.defaultsKey,
        "inline_trailers_enabled", "hero_nuvio_style",
        StageTrendingHeroSetting.defaultsKey, StageTrendingHeroSetting.fullBleedKey,
        "home_upcoming_row_enabled", FocusLeadsRow.defaultsKey, StageInfoBelow.defaultsKey,
        "hero_trailer_autoplay", "trailer_playback_location",
        // Detail page
        DetailSettingsKeys.layout, "detail_action_icons_only", DetailAppleStyle.defaultsKey,
        "detail_poster_backdrop", "detail_trailer_autoplay", "detail_trailer_duration", "trailer_audio_default_on",
        DetailSettingsKeys.sectionStudioLogos, DetailSettingsKeys.sectionParentalGuide,
        DetailSettingsKeys.sectionRatings, DetailSettingsKeys.sectionCast, DetailSettingsKeys.sectionCollection,
        DetailSettingsKeys.sectionTrailers, DetailSettingsKeys.sectionMoreLikeThis,
        DetailSettingsKeys.sectionComments, DetailSettingsKeys.sectionAbout,
        // Player extras
        PlayerTuning.showClockKey,
    ]

    private static let defaultsOnceKey = "orbit.defaults.v1"

    /// Steven (2026-10-24): Orbit's starting values where Nuvio's did not suit it — set once (a
    /// fresh install, or this update); every one stays changeable in Réglages.
    /// - TMDB enrichment on: Orbit's logos, studios, sagas and cast come from it.
    /// - Match the frame rate on (a home cinema: the TV follows the film's rate and range).
    /// - Prepare the next episode on (it starts at once, as on Netflix).
    private static func applyOrbitDefaults(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: defaultsOnceKey) else { return }
        defaults.set(true, forKey: defaultsOnceKey)
        if defaults.object(forKey: PlayerTuning.matchFrameRateKey) == nil {
            defaults.set(true, forKey: PlayerTuning.matchFrameRateKey)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            TmdbSettingsRepository.shared.setEnabled(value: true)
            PlayerSettingsRepository.shared.setPreloadNextEpisodeSources(enabled: true)
        }
    }

    private static let sourcesOnceKey = "orbit.sourcesOrder.v1"

    /// Steven (2026-10-25): Orbit has one source order (French first, see `OrbitStreamRow.sorted`)
    /// and the filters are gone from Réglages; any older choice is put back once, so no hidden
    /// filter keeps hiding sources.
    private static func resetSourceChoices(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: sourcesOnceKey) else { return }
        defaults.set(true, forKey: sourcesOnceKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let debrid = DebridSettingsRepository.shared
            debrid.setStreamSortMode(value: .default_)
            debrid.setStreamMinimumQuality(value: DebridStreamMinimumQuality.any)
            debrid.setStreamDolbyVisionFilter(value: DebridStreamFeatureFilter.any)
            debrid.setStreamHdrFilter(value: DebridStreamFeatureFilter.any)
            debrid.setStreamCachedOnly(enabled: false)
            PlayerSettingsRepository.shared.setStreamAutoPlayCachedOnly(enabled: false)
        }
    }

    static func apply() {
        let defaults = UserDefaults.standard
        defaults.set(NavigationChrome.Style.orbit.rawValue, forKey: NavigationChrome.styleKey)
        defaults.set(HomeLayout.stage.rawValue, forKey: HomeLayout.defaultsKey)
        defaults.set(true, forKey: OrbitHomeSetting.enabledKey)
        // One switch for every trailer ("Lecture automatique des aperçus"): the older pages'
        // trailer gate follows it (the reset had turned it off — default off).
        let previews = defaults.object(forKey: OrbitHomeSetting.trailersKey) as? Bool ?? true
        defaults.set(previews, forKey: "inline_trailers_enabled")

        applyOrbitDefaults(defaults)
        resetSourceChoices(defaults)

        guard !defaults.bool(forKey: onceKey) else { return }
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("debug.") && !keptDebugKeys.contains(key) {
            defaults.removeObject(forKey: key)
        }
        lookKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.set(true, forKey: onceKey)

        // The settings kept by the shared repositories (synced per profile): after launch, once
        // they are up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            CustomPosterUrlRepository.shared.clearPattern()
            PosterCardStyleRepository.shared.resetToDefaults()
            CardDepthStyleRepository.shared.resetToDefaults()
            ThemeSettingsRepository.shared.setAmoled(enabled: false)
            ThemeSettingsRepository.shared.setTheme(theme: .white)
            HomeCatalogSettingsRepository.shared.setHeroEnabled(enabled: true)
            HomeCatalogSettingsRepository.shared.setShowCatalogType(enabled: true)
            PlayerSettingsRepository.shared.setPauseOverlayEnabled(enabled: true)
            PlayerSettingsRepository.shared.setShowLoadingOverlay(enabled: true)
            _ = EpisodeShuffleRepository.shared.setAvailable(available: false)
        }
    }
}
