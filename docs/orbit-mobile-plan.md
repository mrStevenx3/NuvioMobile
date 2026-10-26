# Orbit mobile (iPhone / iPad) — plan

One universal app (iPhone + iPad), SwiftUI, beside the Apple TV app in `iosApp.xcodeproj`.
The Apple TV app is never changed by this work except where a shared file needs a
`#if os(tvOS)` guard around a remote-only API.

## What is shared with the Apple TV app (same files, both targets)

- Data: `SharedCore` (Kotlin, already built for `iosArm64` / `iosSimulatorArm64`): add-ons,
  catalogs, Trakt, profiles, watch progress.
- Orbit's own data: `OrbitMetaStore` (TMDB logos, French posters, ratings, producers),
  `OrbitHomeExtrasModel` (Top 10, platforms' new titles), `OrbitDominantColor`,
  `OrbitPlatformBadge` / `OrbitPlatformLogos`.
- Visual pieces (they take `focused: Bool`, no focus API inside): `OrbitTitleMark`, `OrbitImage`,
  `OrbitSwapImage`, `OrbitPosterCard`, `OrbitLandscapeTile`, `OrbitBigCard`, `OrbitSmallPoster`,
  `OrbitRankedTile` (Top 10), `OrbitMetaLine`, `OrbitRowHeading`, `OrbitProgressBar`,
  `CachedAsyncImage` / `ArtworkStore`.
- Playback: `OrbitPlayerSession` + OrbitEngine (AetherEngine, iOS 18+), Apple's player.
- Trailers: `TrailerHeroPlayer` (zoom policy as on tvOS; full screen uncropped).

A design change to any of these on the Apple TV shows on mobile by itself.

## What is mobile's own (layout only)

Screens assembled for touch: vertical `ScrollView` + horizontal rows scrolled by the finger,
taps instead of focus, a tab bar instead of the Orbit bar. Reordering / removing a block of an
Apple TV screen has to be mirrored here (Claude says so when it happens).

## Steps

1. Target `OrbitMobile` (iOS 18+, iPhone + iPad), app entry, tab bar (Accueil, Films, Séries,
   Plateformes, Recherche, Réglages), profiles, sign-in reused.
2. Home: hero carousel (swipe), rows (classic frame, posters, Top 10, cards, sagas).
3. Title page: hero, Lire / Bande-annonce / Ma liste, episodes, cast, saga, similar.
4. Search (results grid, history).
5. Player (Apple's, OrbitEngine), subtitles, resume.
6. Platforms (Netflix, Disney+, Prime, HBO Max, Paramount+, Apple TV), studios, sagas, library.
7. iPad layouts (wider grids, landscape), polish.

Steps 1–5 make a first installable version; 6–7 follow.

## To check on the Mac when the target is added

- Shared files compiled for iOS: guard tvOS-only APIs (`focusSection`, `onMoveCommand`,
  `onExitCommand`, tvOS transport-bar APIs in `OrbitPlayerViewController`, `UIFocus*`).
- `SharedCore` iOS framework embedded in the new target (same Gradle task as tvOS, iOS slice).
- Signing: IPA built the same way (`orbit5.sh`), installed with the signing service.
