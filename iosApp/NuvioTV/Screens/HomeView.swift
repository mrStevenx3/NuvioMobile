import Combine
import SwiftUI
import UIKit
import SharedCore

/// Home (Steven's fork, 2026-10-24): rebuilt for Orbit only. Chris's classic Home (hero carousel,
/// pinned rows, rail plumbing, settle correctors and probes) is gone; this view is just the
/// navigation shell around Orbit Home (Films / Séries) and the Stage strip (Plateformes, Studios),
/// plus every page they push and the Continue Watching source picker.
struct HomeView: View {
    /// Owned by `ContentView` (above the theme rebuild boundary); this view retains / releases it.
    @ObservedObject var model: HomeViewModel
    @State private var resume: ResumeTarget?
    /// The post-play "More like this" pick from a Continue Watching player, pushed once the
    /// picker cover is gone.
    @State private var homePostPlayPending: MetaPreview?
    @State private var homePath = NavigationPath()
    /// The Apple TV page's posters and the detail page they grow into.
    @Namespace private var zoomSpace
    @State private var isScrolledDown = false
    @AppStorage("home_upcoming_row_enabled") private var upcomingRowEnabled = true

    var body: some View {
        NavigationStack(path: $homePath) {
            ZStack(alignment: .top) {
                Theme.Palette.background.ignoresSafeArea()
                OrbitHomeSwitch(model: model,
                                actions: StageHomeActions(resume: { resume = $0 },
                                                          push: { homePath.append($0) }),
                                pushGenre: { homePath.append(OrbitGenreRoute(genre: $0)) },
                                cover: StageCover(pushed: !homePath.isEmpty, resume: resume != nil),
                                isScrolledDown: $isScrolledDown)
            }
            .navigationDestination(for: TitleRoute.self) { route in
                if route.zoom {
                    DetailView(preview: route.preview, platform: route.platform)
                        .navigationTransition(.zoom(sourceID: route.zoomID, in: zoomSpace))
                } else {
                    DetailView(preview: route.preview, platform: route.platform)
                }
            }
            .navigationDestination(for: CatalogRoute.self) { route in
                CatalogGridView(route: route)
            }
            .navigationDestination(for: PersonRoute.self) { route in
                PersonDetailView(personId: route.id, personName: route.name)
            }
            .navigationDestination(for: EntityRoute.self) { route in
                OrbitStudioPage(route: .entity(route))
            }
            .navigationDestination(for: OrbitStudioRoute.self) { route in
                OrbitStudioPage(route: route)
                    .id(route.openedAt)
            }
            .navigationDestination(for: FolderRoute.self) { route in
                Group {
                if OrbitDisneyPage.handles(route) {
                    OrbitDisneyPage(route: route, push: { homePath.append($0) })
                } else if OrbitNetflixPage.handles(route) {
                    OrbitNetflixPage(route: route, push: { homePath.append($0) })
                } else if OrbitPrimePage.handles(route) {
                    OrbitPrimePage(route: route, push: { homePath.append($0) })
                } else if OrbitHBOPage.handles(route) {
                    OrbitHBOPage(route: route, push: { homePath.append($0) })
                } else if OrbitParamountPage.handles(route) {
                    OrbitParamountPage(route: route, push: { homePath.append($0) })
                } else if OrbitAppleTVPage.handles(route) {
                    // The zoom into the detail page is off (Steven's video, 2026-10-25: it faded through
                    // black instead of growing out of the poster — the page's posters are drawn on one
                    // canvas, not real buttons the zoom can follow). Pass `zoomSpace` to try it again.
                    OrbitAppleTVPage(route: route, push: { homePath.append($0) })
                } else {
                    OrbitPlatformPage(route: route, push: { homePath.append($0) })
                }
                }
                // Steven (the page showed for an instant before its logo's opening): black over its
                // very first frames, until the opening's own black has taken over.
                .overlay { OrbitOpeningCover() }
                .id(route.openedAt)
            }
            .navigationDestination(for: OrbitGenreRoute.self) { route in
                OrbitGenrePage(genre: route.genre)
            }
            .fullScreenCover(item: $resume, onDismiss: {
                guard let pick = homePostPlayPending else { return }
                homePostPlayPending = nil
                homePath.append(TitleRoute(preview: pick))
            }) { target in
                StreamPickerView(
                    type: target.entry.parentMetaType,
                    videoId: target.entry.videoId,
                    title: target.entry.title,
                    parentMetaId: target.entry.parentMetaId,
                    season: target.entry.seasonNumber?.value,
                    episode: target.entry.episodeNumber?.value,
                    poster: target.entry.poster,
                    episodeStill: { let still: String? = target.entry.episodeThumbnail; return (still ?? "").isEmpty ? nil : still }(),
                    synopsis: { let d: String? = target.entry.pauseDescription; return (d ?? "").isEmpty ? nil : d }(),
                    forceManual: target.forceManual,
                    startFromBeginning: target.startFromBeginning,
                    onOpenTitle: { homePostPlayPending = $0 }
                )
            }
        }
        .environment(\.orbitPush, { homePath.append($0) })
        .environment(\.orbitPushFolder, { homePath.append($0) })
        .environment(\.orbitPushStudio, { homePath.append($0) })
        // The black a platform's page is pushed under (its opening lifts it).
        .overlay { OrbitPlatformCurtainView() }
        .orbitPopsToRootOnGoHome($homePath, tab: 0, delay: 0)
        .onAppear {
            // Retain, don't start: during a theme rebuild the incoming Home appears before the
            // outgoing one disappears, so the count goes 1 → 2 → 1 and the pipeline never restarts.
            model.acquire()
            if upcomingRowEnabled { model.startUpcoming() }
        }
        .onDisappear { model.release() }
        .onChange(of: upcomingRowEnabled) { _, enabled in
            if enabled { model.startUpcoming() } else { model.stopUpcoming() }
        }
    }
}

extension HomeView {
    /// The one-line description under a focused collection folder: the folder's own name (its
    /// wordmark may be an image) and how many sources feed it.
    nonisolated static func folderHeroDescription(collection: NuvioCollection, folder: CollectionFolder) -> String {
        let name = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = folder.resolvedSources.count
        let count: String
        switch sources {
        case 0: count = String(localized: "Collection folder")
        case 1: count = String(localized: "1 source")
        default: count = String(localized: "\(sources) sources")
        }
        return name.isEmpty ? count : "\(name) \u{00B7} \(count)"
    }
}

extension RowRestSource {
    /// beta.19-rc1 verdict (review r1, A P2): the rows have not moved for
    /// `TrailerStartGate.restQuiet`, whatever the settle corrector's pending flag says: `isAtRest()`
    /// with `restPending` read as false, over the same clocks per source. The hero sharpen's rest
    /// ceiling releases only on a quiet stretch (`HeroSharpen.restStep`'s `quietAge`), so a stuck
    /// settle decision gives way and real motion never does.
    @MainActor var rowsQuiet: Bool {
        let since: TimeInterval
        switch self {
        case .motionClock:
            since = RowsMotionClock.secondsSinceMotion()
        case .pinnedHome:
            since = RowsMotionClock.secondsSinceMotion()
        case .custom(let signal):
            since = signal.secondsSinceMotion
        }
        return TrailerStartGate.isAtRest(sinceMotion: since, restPending: false)
    }
}

/// Identifiable wrapper so a progress entry can drive `.fullScreenCover(item:)` for direct resume.
struct ResumeTarget: Identifiable {
    let entry: WatchProgressEntry
    /// Hold menu "Play Manually": open the picker without auto-selecting a source.
    var forceManual: Bool = false
    /// Hold menu "Start Over": play from 0 instead of the saved position.
    var startFromBeginning: Bool = false
    var id: String { entry.videoId }
}

/// BUG-42 (beta.13): release-safe hero commit probe — `defaults write com.nuvio.media.NuvioTV
/// debug.homeHeroProbe -bool YES`, greppable `[HomeHero]`. Same house pattern as
/// `HomeGeometryProbe`/`TrailerProbe` (deliberately not `#if DEBUG`: the reporter is on a release
/// sideload and the console is the only thing that comes back from a device pass). Two lines:
/// `publish` (from `HomeViewModel`, per hero-bearing state) and `paint` (from
/// `HeroCrossfadeImage.crossfade`, per image swap). A healthy cold launch shows exactly ONE
/// `paint first=1` and NO `publish … headChanged=1`.
enum HomeHeroProbe {
    /// BUG-42 (beta.13.5): the defaults knob stays for local/device-pass use, but the reporter is
    /// on a sideload with no way to `defaults write` — Settings → About now exposes the same knob
    /// as a toggle (`heroDiagnosticsKey`), and the probe lines are mirrored into a small persisted
    /// ring buffer the About pane renders, so a cold-launch capture is one TV photo away.
    nonisolated static let enabled = UserDefaults.standard.bool(forKey: "debug.homeHeroProbe")
    nonisolated static let t0 = Date()
    // nonisolated (Codex round 1): the target defaults to MainActor isolation, and the
    // nonisolated `log` below reads this — pure Date math, safe from any executor.
    nonisolated static var sinceLaunchMs: Int { Int(Date().timeIntervalSince(t0) * 1000) }

    nonisolated static let linesKey = "debug.homeHeroProbe.lines"
    /// H-1A (beta.15): the buffer used to be a flat 24-line ring, front-evicted — so on a busy
    /// cold launch (addons syncing, rows filling in, hero enrichment landing) the LAUNCH HEAD —
    /// exactly the diagnostically valuable part: init, first publish, first paint — was the first
    /// thing evicted once logging ran past 24 lines, and a tester's photo of the About pane showed
    /// only recent noise with the actual double-paint evidence already gone. Now HEAD-PRESERVING:
    /// the first `headMaxLines` lines are captured once and never evicted; only the TAIL rolls,
    /// keeping the most recent `tailMaxLines`. A single elision marker line separates the two once
    /// eviction has actually started (never shown on a launch short enough that nothing was
    /// dropped). Max displayed lines: `headMaxLines` + 1 marker + `tailMaxLines` = 57.
    ///
    /// Wave H raised the head 16 → 24: the launch head now carries a `present` line per hero commit
    /// alongside the `publish`/`paint`/`commit` lines, and the photo contract the device pass reads
    /// (one publish before the first commit, `gate=`, zero `headChanged`/`same=1`) has to fit
    /// inside the frozen head or the evidence rolls out of the pane before the tester photographs
    /// it — the exact failure H-1A introduced the head-preserving buffer for.
    nonisolated static let headMaxLines = 24
    nonisolated static let tailMaxLines = 32
    nonisolated(unsafe) private static var headLines: [String] = []
    nonisolated(unsafe) private static var tailLines: [String] = []
    /// Lines dropped from the tail stream once `tailLines` is full. Stays 0 (no marker rendered)
    /// until eviction genuinely begins.
    nonisolated(unsafe) private static var elidedTailCount = 0
    nonisolated private static let bufferLock = NSLock()

    /// H-1A: monotonic per-process instance counter, guarded by `bufferLock` alongside the ring
    /// buffer it stamps lines for. `HomeViewModel`/`HeroCrossfadeImage` each mint one id at init
    /// and stamp it (`vm=<n>` / `item=<id>`) into every probe line they log, so a photographed
    /// pane can tell two overlapping instances apart instead of interleaving their lines under one
    /// identity — exactly the ambiguity a sync-driven theme remount (see `AppThemeModel`) produces.
    nonisolated(unsafe) private static var nextInstanceId = 0
    nonisolated static func newInstanceId() -> Int {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        nextInstanceId += 1
        return nextInstanceId
    }

    /// NSLogs `line` (the greppable `[HomeHero]` console contract is unchanged) and appends it to
    /// the persisted, head-preserving ring buffer. `headLines`/`tailLines` are fresh statics for
    /// this process, so the very first call of a launch already starts the buffer clean — no
    /// separate "did we reset yet" flag needed (the old flat-ring implementation carried one; it's
    /// moot once the head is captured once and frozen rather than continuously re-derived from
    /// whatever UserDefaults happened to hold from the previous launch).
    nonisolated static func log(_ line: String) {
        NSLog("[HomeHero] %@", line)
        bufferLock.lock()
        defer { bufferLock.unlock() }
        let stamped = "\(sinceLaunchMs)ms \(line)"
        if headLines.count < headMaxLines {
            headLines.append(stamped)
        } else {
            tailLines.append(stamped)
            if tailLines.count > tailMaxLines {
                tailLines.removeFirst()
                elidedTailCount += 1
            }
        }
        var display = headLines
        if elidedTailCount > 0 {
            display.append("\u{2026} \(elidedTailCount) lines elided \u{2026}")
        }
        display.append(contentsOf: tailLines)
        UserDefaults.standard.set(display, forKey: linesKey)
    }
}

#if DEBUG

#endif

let collectionHeroType = "nuvio.folder"
let collectionHeroIdScheme = "nuvio-folder://"

/// Resolves the logo artwork URL for a hero item. Catalog previews (Cinemeta rows especially)
/// usually omit `logo` even when logo art exists, so for IMDb-id items fall back to metahub —
/// the same CDN Cinemeta's own full meta points at. A miss there just 404s and `HeroLogo`
/// shows its text wordmark, so the synthesized URL is strictly additive (BUG-17).
func heroLogoURL(for item: MetaPreview) -> URL? {
    heroLogoURL(logo: item.logo, id: item.id)
}

/// Same chain for a Continue Watching entry, so the CW row's prefetch warms the logo the hero will
/// actually wait on (`background`/`parentMetaId` play the banner/id roles, exactly as they do for
/// `heroBackdropURL(for:)`).
func heroLogoURL(for entry: WatchProgressEntry) -> URL? {
    heroLogoURL(logo: nil, id: entry.parentMetaId)
}

private func heroLogoURL(logo: String?, id: String) -> URL? {
    if let logo, !logo.isEmpty { return URL(string: logo) }
    let imdbId = id.split(separator: ":").first.map(String.init) ?? id
    guard imdbId.hasPrefix("tt") else { return nil }
    return URL(string: "https://images.metahub.space/logo/medium/\(imdbId)/img")
}

/// Resolves the backdrop artwork URL for a hero item — a carousel page, or (UX-7) a row poster
/// that has taken over the hero. `banner` covers the common case; IMDb-id items without one fall
/// back to metahub's background art (the same CDN `heroLogoURL` leans on above) before finally
/// falling back to poster art. Every step is strictly additive — a miss just moves to the next
/// source, never a hard failure.
func heroBackdropURL(for item: MetaPreview) -> String? {
    heroBackdropURL(banner: item.banner, id: item.id, poster: item.poster)
}

/// Same chain for a Continue Watching entry (`background` plays the banner role, the parent meta
/// id carries the IMDb id) — the CW row's prefetch must warm the URL the hero will actually
/// render, not a poster the metahub branch would shadow.
func heroBackdropURL(for entry: WatchProgressEntry) -> String? {
    heroBackdropURL(banner: entry.background, id: entry.parentMetaId, poster: entry.poster)
}

private func heroBackdropURL(banner: String?, id: String, poster: String?) -> String? {
    if let banner, !banner.isEmpty { return banner }
    let imdbId = id.split(separator: ":").first.map(String.init) ?? id
    if imdbId.hasPrefix("tt") {
        return "https://images.metahub.space/background/medium/\(imdbId)/img"
    }
    return (poster?.isEmpty == false) ? poster : nil
}

/// Page-position dots for the hero carousel. Rendered once, outside the sliding pages, so they
/// stay put while the carousel animates.
struct HeroPageDots: View {
    let count: Int
    let index: Int

    /// Capsule height of each dot.
    nonisolated static let dotHeight: CGFloat = 10
    /// The laid-out height of this view: a dot plus the vertical padding. Read by
    /// `Theme.Size.heroPinnedRowsViewportBudget(showsCTA:)`, whose panel-form budget is taller by
    /// exactly this plus the header's `Spacing.sm` (2026-09-30), so the two cannot drift.
    nonisolated static let height: CGFloat = dotHeight + 2 * Theme.Spacing.xs

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index
                          ? Theme.Palette.textPrimary
                          : Theme.Palette.textSecondary.opacity(0.45))
                    .frame(width: i == index ? 34 : 10, height: Self.dotHeight)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .glassEffect(.regular, in: .capsule)
        .animation(.easeInOut(duration: 0.3), value: index)
        .accessibilityHidden(true)
    }
}

#if DEBUG

#endif


/// Black over a platform page's first frames (its opening covers it from there).
private struct OrbitOpeningCover: View {
    @State private var gone = false

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .opacity(gone ? 0 : 1)
            .allowsHitTesting(false)
            .task {
                try? await Task.sleep(for: .milliseconds(250))
                gone = true
            }
    }
}
