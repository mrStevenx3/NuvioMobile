# Orbit — handoff (fork de NuvioTV par Chris, pour Steven)

Dépôt : github.com/mrStevenx3/NuvioMobile, branche **tvos-shared-extraction** (= Orbit).
Workflow CI : `.github/workflows/build-ipa.yml` (IPA non signé → Signulous). Secrets du dépôt :
SUPABASE_URL, SUPABASE_ANON_KEY, TMDB_API_KEY (lus dans local.properties au build).
Build CI réussi avec Xcode 26.6 (macos-26). App : nom « Orbit », bundle com.mrstevenx3.orbit.

## Fait (tous désactivables dans Réglages)
- Accueil : titre sélectionné calé à gauche (`FocusLeadsRow`, BrowseComponents.swift / HomeView.swift),
  gap 14 pt, view-aligned + scrollTo(id:anchor:.leading) au runloop suivant.
- Accueil Stage : « Infos sous l'affiche » (`StageInfoBelow`, StripGeometry/StageView/StripPager/StageSwapModel).
- Détail Cinematic « Style Apple TV » (`DetailAppleStyle`, DetailCinematicHero/DetailView) : synopsis à droite
  + chevron (déroulé en place), crédits en bas à droite, héros plein écran sans aperçu de la 1re rangée (`fullScreenHeroHeight`, `heroBottomInset`), flou bas ; en défilant le fond se floute (`DetailBackdropBlur`, sans assombrir), logo compact qui glisse vers le haut (pas de zoom). Guide parental : suit seulement son réglage (Réglages > Détail).
- Fix CI : NativeSubtitleStyle (type-check), import SwiftUI.

## À faire (retours device de Steven)
1. Défilement accueil : un pas sur deux saute encore (à confirmer sur ce build) — régler en simulateur.
2. Carte sélectionnée en paysage d'office + animation façon wako (InlineTrailerCard ne s'élargit qu'au trailer).
3. Infos sous l'affiche : encore un peu trop bas ? (StageInfoBelow.pullUp)
4. Idées : barre du haut perso [🏠] Films Séries Plateformes [🔍→Découvrir] … [⚙️] heure ;
   section Plateformes avec animation de l'icône Orbit.

## Mac loué (Scaleway M1-M, macOS Tahoe 26, Xcode installé)
Préparer : Java 17 (temurin), `git clone` + `git submodule update --init MPVKit`,
quickjs-kt 1.0.5-tvos via `scaffolding/build-quickjs-tvos.sh` du dépôt youngchris29-art/NuvioTV @6265f00,
local.properties (mêmes clés que les secrets), puis `./gradlew :shared:linkDebugFrameworkTvosSimulatorArm64`
et xcodebuild scheme NuvioTV (simulateur tvOS, ARCHS=arm64). 8 Go de RAM : GRADLE_OPTS=-Xmx4g.
