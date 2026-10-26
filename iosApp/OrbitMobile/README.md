# Orbit mobile (iPhone / iPad) — first draft

Steps 1–5 of `docs/orbit-mobile-plan.md`, written without a compiler: expect a round of small fixes
on the Mac. Nothing outside this folder was changed.

## Files

| File | What |
|---|---|
| `OrbitMobileApp.swift` | `@main`; `NuvioTVApp.init()`'s non-TV launch work; the auth → profile → shell gate (`ContentView`'s flow); placeholder sign-in and "Qui regarde ?" screens built on `AuthViewModel` / `ProfilesViewModel` |
| `OrbitMobileRoot.swift` | Tab bar: Accueil, Films, Séries, Plateformes (placeholder), Réglages (placeholder), Recherche |
| `OrbitMobileHome.swift` | Touch Home: swiped hero, rows of the TV's own tiles scaled down; `OrbitHomeRowsBuilder` (see "To extract") |
| `OrbitMobileDetail.swift` | Title page v1: backdrop, logo, meta line, synopsis, Lire / Ma liste / Vu, episodes, cast; Lire presents `StreamPickerView` exactly as `OrbitDetailView` does |
| `OrbitMobileSearch.swift` | `.searchable` + poster grid on `SearchViewModel` (+ recent searches) |
| `OrbitMobileTVShims.swift` | No-op iOS stand-ins for the remote's SwiftUI APIs used by the shared files (see "tvOS-only APIs") |
| `Info.plist` | The mobile target's plist (merged with the generated one) |

Why the placeholders: `WelcomeView`, `AuthView`, `QrSignInView`, `OrbitProfilePicker`,
`OrbitProfileEditor`, `OrbitSettingsView` and `OrbitSearchView` (`UISearchContainerViewController`)
are built for the remote (FocusState navigation, `onExitCommand`, focus-lift button styles,
1920-point layouts). The mobile screens reuse their view models and `OrbitAvatar` instead.

## Target setup (Xcode 26)

1. File › New › Target › iOS App, name **OrbitMobile**, SwiftUI, Swift. Delete the template's
   App/ContentView/Assets files. Devices iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`).
2. Deployment target: **iOS 26.0 recommended** (see open questions). With iOS 18, wrap the two
   `.glassEffect` calls listed below in `if #available(iOS 26, *)` and expect a few more
   "only available in iOS 26" errors from code written for tvOS 26.
3. Build settings to copy from NuvioTV: `SWIFT_VERSION = 5.0`,
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`,
   `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`, `STRING_CATALOG_GENERATE_SYMBOLS = YES`,
   `SWIFT_EMIT_LOC_STRINGS = YES`, `ENABLE_USER_SCRIPT_SANDBOXING = NO` (the Gradle phase writes
   outside the sandbox), `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_FILE = OrbitMobile/Info.plist`,
   `INFOPLIST_KEY_UILaunchScreen_Generation = YES`, `LD_RUNPATH_SEARCH_PATHS = $(inherited) @executable_path/Frameworks`.
4. Sources:
   - Add the `OrbitMobile` folder as a synchronized group, member of **OrbitMobile only**, with
     `Info.plist` and `README.md` as membership exceptions.
   - Tick **OrbitMobile** in the target membership of the existing `NuvioTV` synchronized folder,
     then untick the files listed under "Not compiled" (plus `Info.plist`, `NuvioTV.entitlements`).
     The Apple TV target is untouched.
   - Packages: add the local `OrbitEngine` product to the target's Frameworks (its manifest already
     declares `.iOS(.v18)`). MPVKit is not needed (no NuvioTV file imports it).
5. App icon: the shared `Assets.xcassets` only holds the tvOS brand asset. Add an `AppIcon` set
   (1024 px, single size) and set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

### Existing NuvioTV files the mobile target compiles (127)

Found by following every type/function each file uses, starting from the mobile files (a
heuristic: if a symbol is missing, add the file that declares it). `HomeView.swift` is what pulls in
every platform page (it declares `HomeHeroProbe`, `heroBackdropURL`, `ResumeTarget`, used by
`HomeViewModel` and the tiles); moving those few declarations to their own file would drop ~15 pages.

- `NuvioTV/Bridge/` (1): SharedStringProvider.swift
- `NuvioTV/DesignSystem/` (22): AnimatedGifImage.swift, ArtworkColorStore.swift, ArtworkDecodeSize.swift, ArtworkLetterbox.swift, ArtworkURLUpgrade.swift, CachedAsyncImage.swift, CardDepthStyle.swift, FlatControlStyles.swift, FocusAppearance.swift, FocusRow.swift, HiddenTabBarFocusBlocker.swift, LaunchTrace.swift, OrbitSpaceTransition.swift, OrbitTopBar.swift, PosterCard.swift, PosterStyle.swift, StageLocalizedCopyStore.swift, SystemKeyboardFocus.swift, TabBarVisibility.swift, Theme.swift, TitleHoldMenu.swift, TitleLogoStore.swift
- `NuvioTV/Screens/` (43): AuthViewModel.swift, BrowseComponents.swift, CatalogGridView.swift, CatalogGridViewModel.swift, CollectionsUI.swift, ContinueWatchingDebugSeed.swift, DetailView.swift, DetailViewModel.swift, EpisodeSpoilerRules.swift, EpisodesSection.swift, ExternalPlaybackReturn.swift, FolderRowsPlan.swift, HomeBodyCounter.swift, HomeHeroCommit.swift, HomeView.swift, HomeViewModel.swift, InlineTrailerCard.swift, NextEpisodeAutoPlay.swift, PersonDetailView.swift, PersonDetailViewModel.swift, PlaybackModels.swift, PlaybackProgressRecorder.swift, PlayerScreen.swift, ProfileAutoEnter.swift, ProfilesViewModel.swift, RejectedStreamLinks.swift, RemoteSetupWebPage.swift, SearchPerfProbe.swift, SearchPolicies.swift, SearchView.swift, SearchViewModel.swift, StreamPickerView.swift, StreamProbe.swift, StreamsViewModel.swift, TopShelfSnapshot.swift, TrailerBridge.swift, TrailerDebugProbes.swift, TrailerHealthProbe.swift, TrailerHeroPlayerView.swift, TrailerLocalHLS.swift, TrailerStartGate.swift, TrailerThumbnail.swift, TrailerZoomProbe.swift
- `NuvioTV/Screens/Detail/` (3): DetailAboutSection.swift, DetailCinematicLayout.swift, DetailSynopsisSheet.swift
- `NuvioTV/Screens/Discover/` (3): DiscoverGenreNames.swift, DiscoverRowsLoader.swift, DiscoverRowsPlan.swift
- `NuvioTV/Screens/Home/` (9): HomeLayout.swift, HomePerfKnobs.swift, HomeRowPreviews.swift, StageCopy.swift, StageTrendingHero.swift, StripPager.swift, StripRowsPlan.swift, ViewerInput.swift, ViewerInputClock.swift
- `NuvioTV/Screens/OrbitHome/` (29): OrbitAppleTVPage.swift, OrbitDetailPlatform.swift, OrbitDetailView.swift, OrbitDisneyPage.swift, OrbitEpisodesSection.swift, OrbitGenrePage.swift, OrbitHBOPage.swift, OrbitHomeHero.swift, OrbitHomeLayout.swift, OrbitHomeRow.swift, OrbitHomeTiles.swift, OrbitHomeView.swift, OrbitMetaStore.swift, OrbitNativeHome.swift, OrbitNativeSections.swift, OrbitNavigation.swift, OrbitNetflixPage.swift, OrbitParamountPage.swift, OrbitPlatformBadge.swift, OrbitPlatformPage.swift, OrbitPlatformSearch.swift, OrbitPlatformTrending.swift, OrbitPrimePage.swift, OrbitQualityBadges.swift, OrbitSearchResultsController.swift, OrbitSpacesPage.swift, OrbitStreamList.swift, OrbitStudioPage.swift, OrbitStudiosPage.swift
- `NuvioTV/Screens/OrbitPlayer/` (4): OrbitLoadingView.swift, OrbitPlayerOverlays.swift, OrbitPlayerSession.swift, OrbitPlayerViewController.swift
- `NuvioTV/Screens/OrbitProfiles/` (2): OrbitAvatarCatalog.swift, OrbitProfileKit.swift
- `NuvioTV/Screens/OrbitSources/` (2): OrbitAutoPlay.swift, OrbitExternalHandOff.swift
- `NuvioTV/Screens/Player/` (5): NetworkPathMonitor.swift, PlaybackFailureClassifier.swift, PlayerAudioLanguagePlan.swift, PlayerChipStyle.swift, SkipSegmentPlanner.swift
- `NuvioTV/Screens/Search/` (4): CollectionSearchLayer.swift, SearchGridResults.swift, SearchResultsPolicy.swift, SearchRowsMode.swift

Resources, also members: `Assets.xcassets` (OrbitMark, platform marks, quality badges),
`Localizable.xcstrings`, `Shared.xcstrings`, `Resources/Fonts/*.ttf`. Both targets share
`Localizable.xcstrings`: the mobile files' new French keys get added to it on build (additions only).

### Not compiled (untick OrbitMobile on these 42)

`NuvioTVApp.swift` (second `@main`), `ContentView.swift`, `DesignSystem/`: AmbientWashLayer,
AppThemeModel, FilterPills, NavigationChrome, RowEdgeEffectStyle, WatchedBadgeIndex;
`Screens/`: AuthView, CloudLibraryUI, DebridViewModel, DeepLink, LibraryGridPolicy, LibraryView,
LibraryViewModel, MdbListViewModel, PluginsViewModel (uses the tvosMain-only `PluginRepository`),
QrSignInView, RemoteSetupServer, RemoteSetupViewModel, ServerConnectionView,
ServerConnectionViewModel, SettingsViewModel, SimklViewModel, TraktViewModel, WelcomeView,
`Detail/DetailSettingsKeys`, `Discover/`: DiscoverGridModel, DiscoverPlacement, DiscoverTabRoot,
`Home/StripGeometry`, `OrbitHome/`: OrbitDiscoverPage, OrbitLibraryPage, OrbitSearchView,
`OrbitProfiles/`: OrbitProfileEditor, OrbitProfilePage, OrbitProfilePicker, `OrbitSettings/`:
OrbitSettingsKit, OrbitSettingsPins, OrbitSettingsSections, OrbitSettingsView,
`Player/HarvestCrashSentinel`.

## tvOS-only APIs in the compiled files

**Must be guarded** with `#if os(tvOS)` (AVKit members with no iOS equivalent; the plan already
expected this file):

| File | Lines · API |
|---|---|
| `Screens/OrbitPlayer/OrbitPlayerViewController.swift` | 43 `appliesPreferredDisplayCriteriaAutomatically`; 45, 132 `contextualActions` (skip intro / next episode); 142, 150 `transportBarCustomMenuItems` (audio menu) |

On iOS those features need an overlay of our own (step 5). `pressesBegan` and `UIPress` types exist
on iOS and compile as is.

**iOS 26-only** (only if the deployment target stays below 26): `DesignSystem/FlatControlStyles.swift:138`
and `Screens/HomeView.swift:330` — `.glassEffect`.

**Covered by `OrbitMobileTVShims.swift`** (no edit needed if the shims resolve; otherwise remove the
failing shim and guard these lines):

| File | Lines · API |
|---|---|
| `DesignSystem/FocusRow.swift` | focusSection 18 |
| `DesignSystem/OrbitTopBar.swift` | focusSection 164, 497, 512, 730 |
| `Screens/Detail/DetailSynopsisSheet.swift` | onMoveCommand 67 |
| `Screens/OrbitHome/OrbitAppleTVPage.swift` | MoveCommandDirection 506 |
| `Screens/OrbitHome/OrbitDetailView.swift` | focusSection 235, 704, 715, 831, 860, 887, 914, 969; onExitCommand 315, 360, 1468; onMoveCommand 355 |
| `Screens/OrbitHome/OrbitDisneyPage.swift` | MoveCommandDirection 423 |
| `Screens/OrbitHome/OrbitEpisodesSection.swift` | focusSection 100, 138 |
| `Screens/OrbitHome/OrbitHBOPage.swift` | MoveCommandDirection 512 |
| `Screens/OrbitHome/OrbitNativeHome.swift` | onMoveCommand 80, 393; onExitCommand 109; focusSection 167, 392; MoveCommandDirection 189, 297 |
| `Screens/OrbitHome/OrbitNativeSections.swift` | MoveCommandDirection 71, 103; focusSection 123, 132; onMoveCommand 124, 133, 145; onExitCommand 159 |
| `Screens/OrbitHome/OrbitNavigation.swift` | onExitCommand 137; onMoveCommand 142 |
| `Screens/OrbitHome/OrbitNetflixPage.swift` | MoveCommandDirection 392 |
| `Screens/OrbitHome/OrbitParamountPage.swift` | MoveCommandDirection 426 |
| `Screens/OrbitHome/OrbitPlatformPage.swift` | MoveCommandDirection 330 |
| `Screens/OrbitHome/OrbitPlatformSearch.swift` | UISearchContainerViewController 156 (stub class in the shims) |
| `Screens/OrbitHome/OrbitPlatformTrending.swift` | focusSection 339 |
| `Screens/OrbitHome/OrbitPrimePage.swift` | MoveCommandDirection 467 |
| `Screens/OrbitHome/OrbitStudioPage.swift` | onExitCommand 399; onMoveCommand 436; focusSection 446, 782; MoveCommandDirection 471 |
| `Screens/OrbitHome/OrbitStudiosPage.swift` | focusSection 126, 662; onExitCommand 137 |
| `Screens/OrbitProfiles/OrbitProfileKit.swift` | onExitCommand 162 |
| `Screens/PersonDetailView.swift` | focusSection 54, 56; focusScope 73; prefersDefaultFocus 156 |
| `Screens/Search/CollectionSearchLayer.swift` | focusSection 27; onExitCommand 28 |
| `Screens/Search/SearchGridResults.swift` | focusSection 51, 67 |
| `Screens/StreamPickerView.swift` | focusSection 281, 289; onExitCommand 766 |
| `Screens/TrailerHeroPlayerView.swift` | onPlayPauseCommand 620 |

UIKit focus APIs (`UIFocusSystem`, `focusedItem`, `UIFocusUpdateContext`, `allowedPressTypes`)
exist on iOS and compile; they simply never fire on touch.

## Info.plist and entitlements

`OrbitMobile/Info.plist`: display name Orbit, ATS arbitrary loads (http add-ons), local-network
usage text, `LSApplicationQueriesSchemes` infuse + nativeplayer (the two players
`ExternalPlayerPlatform.apple.kt` knows), the per-install `$(PRODUCT_BUNDLE_IDENTIFIER)` URL scheme
(Infuse's x-callback return, read by `AppCallbackScheme`), the Open Sans fonts, background audio,
dark style, orientations. No `nuviotv` scheme: Top Shelf deep links are TV-only.

Entitlements: none required for v1. The app group `group.com.nuvio.media.NuvioTV` is only used by
`TopShelfSnapshot` (nil-safe without it). Background audio is declared in the plist; Picture in
Picture can come later (the TV player sets `allowsPictureInPicturePlayback = false`).

## SharedCore for iOS

`shared/build.gradle.kts` already declares `iosArm64()` / `iosSimulatorArm64()` with the same
`SharedCore` framework, **static** (`isStatic = true`): it is linked, not embedded (no Embed phase).
The TV target's "Compile Kotlin Framework" run script maps the SDK to a Konan target; for the mobile
target add a run-script phase (before Compile Sources, same JAVA_HOME/GRADLE_OPTS preamble) with:

```sh
case "$CONFIGURATION" in Release*|release*) CFG="Release" ;; *) CFG="Debug" ;; esac
case "$SDK_NAME" in
  iphoneos*) KONAN_TARGET="IosArm64" ;;
  iphonesimulator*) KONAN_TARGET="IosSimulatorArm64" ;;
  *) echo "error: OrbitMobile shared-framework build: unsupported SDK '$SDK_NAME'"; exit 1 ;;
esac
cd "$SRCROOT/.."
./gradlew ":shared:link${CFG}Framework${KONAN_TARGET}"
```

Build settings (Debug; Release uses `releaseFramework`):

```
FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]        = $(SRCROOT)/../shared/build/bin/iosArm64/debugFramework
FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*] = $(SRCROOT)/../shared/build/bin/iosSimulatorArm64/debugFramework
OTHER_LDFLAGS = $(inherited) -framework SharedCore
```

Not on iOS: `TvOsPluginsInstallerKt.installTvOsPlugins()` (tvosMain, QuickJS fork with tvOS
targets only), so no JS scrapers; the add-ons' streams work. `installTvOsSharedProviders()` is in
appleMain and runs as on the TV. Every `expect` in commonMain has an appleMain actual, so the iOS
slice links. Signing / IPA: `orbit5.sh` builds the TV scheme; it needs an `OrbitMobile` scheme +
`-sdk iphoneos` pass for the phone IPA.

## To extract (shared builder)

`OrbitHomeRowsBuilder` in `OrbitMobileHome.swift` is a copy of `OrbitHomeView`'s private
`buildRows()`, `rowsSignature()`, `card(_:_:)`, `becauseSeed(series:)` and `unique(_:)`
(`Screens/OrbitHome/OrbitHomeView.swift`). Move the enum to
`Screens/OrbitHome/OrbitHomeRowsBuilder.swift` (both targets), have `OrbitHomeView.rows` call
`OrbitHomeRowsBuilder.rows(series:model:extras:)` and `.signature(...)`, and delete the private
copies, so a row reordered on the TV reorders on mobile too. Until then, mirror any change by hand.

## v1 gaps

- Plateformes and Réglages are placeholders (badges list; profile switch + sign-out).
- Detail: no trailer, saga, similar, about, quality badges; cast is not tappable (`PersonDetailView`
  is a TV layout).
- Player: the TV's `StreamPickerView` / `PlayerScreen` / `OrbitPlayerViewController` as they are —
  the source list is laid out for 1920 points (it will look large on a phone) and skip-intro /
  next-episode / audio menu are TV-only until step 5.
- No hero or row trailers on mobile.
