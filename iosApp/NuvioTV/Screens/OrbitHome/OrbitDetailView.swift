import Combine
import SharedCore
import SwiftUI

// Orbit Detail (Steven, 2026-10-23): the film / series page rebuilt from scratch for Orbit (the old
// page is kept, as `LegacyDetailView`, for the other navigation modes only). The data and every
// action are `DetailViewModel`'s; the page is new:
//
//  - ONE fixed background: the title's backdrop over the whole screen. On the hero it is clear,
//    under the sections it goes dark and soft, so text reads on any art (a bright Pixar still too).
//  - The hero, the first screen: logo (or name), a plain meta line ("2001 · 1 h 32 · Animation,
//    Comédie · U · ★ 8,1"), the actions (Lire / Reprendre, Recommencer, Bande-annonce, Vu, Ma
//    liste — the focused one says its name), the synopsis on the same line (its arrow opens it in
//    full in a panel), "Avec … · Réalisé par …" small at the bottom right, the art's bottom blurred. The muted trailer plays behind it after a
//    rest on the hero.
//  - Then the sections, each a row: Épisodes (series), Casting, the saga, Bandes-annonces,
//    À voir aussi, À propos (studios' logos, parental guide, details in plain French).
//  - The hero is part of the scrolled content, never a second copy: nothing appears twice.
//    Each section the focus enters is brought to the top of the screen on one curve; back in the
//    hero, the page returns to the top. Menu from a section goes back to the hero; from the hero
//    it leaves the page.

/// Every focusable place on the page, so the page knows which section holds the focus.
enum OrbitDetailFocus: Hashable {
    case play, restart, trailer, watched, library, synopsis
    case cast(Int)
    case saga(String)
    case trailerClip(String)
    case similar(String)
    case company(Int)
    case about
    case season(Int)
    case episode(String)

    var section: OrbitDetailSection {
        switch self {
        case .play, .restart, .trailer, .watched, .library, .synopsis: return .hero
        case .cast: return .cast
        case .saga: return .saga
        case .trailerClip: return .trailers
        case .similar: return .similar
        case .company, .about: return .about
        case .season, .episode: return .episodes
        }
    }
}

enum OrbitDetailSection: Hashable {
    case hero, episodes, cast, saga, trailers, similar, about
}

enum OrbitDetailLayout {
    static let margin: CGFloat = OrbitHomeLayout.margin
    /// The hero's height: the first section's heading peeks at the bottom of the first screen.
    /// The first screen exactly (Steven: the "C" of Casting peeked under the hero).
    static let heroHeight: CGFloat = 1080
    static let sectionGap: CGFloat = 70
    /// Where a section's top rests on screen when the focus is in it.
    /// Steven (the page bounced on Left / Right): low enough that the focused card, lifted, sits
    /// well inside the screen, so the system has no reason to move the page itself.
    static let sectionRest: CGFloat = 200
    /// The episodes section's top (it holds the season posters, the episodes and their text).
    static let episodesRest: CGFloat = 100
    /// The line the system aligns a focused section's top on (the page's top margin).
    static let pageTop: CGFloat = 140
}

/// Every route to a title opens the Orbit page (Steven: the old page is retired).
/// When a title's page last appeared (a page going away just before was covered, not closed).
@MainActor
enum OrbitNavClock {
    static var titleOpenedAt: TimeInterval = 0
    /// Title pages on screen (a page going away while one shows was covered, not closed).
    static var titlesShown = 0
}

struct DetailView: View {
    let preview: MetaPreview
    /// The platform page it was opened from, if any (its light touch).
    var platform: OrbitDetailPlatform? = nil

    var body: some View {
        OrbitDetailView(preview: preview, platform: platform)
    }
}

struct OrbitDetailView: View {
    let preview: MetaPreview
    /// Steven (2026-10-25): opened from a platform page, the page takes its light touch — its logo
    /// top right, its "original" tag above the title, its Lecture button, its tint under the sections.
    var platform: OrbitDetailPlatform? = nil

    @StateObject private var model: DetailViewModel
    /// Steven: 4K / Dolby Vision / HDR / Atmos when his sources have them.
    @StateObject private var quality = OrbitQualityModel()
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("detail_trailer_background") private var backgroundTrailerEnabled = true

    @FocusState private var focus: OrbitDetailFocus?
    @State private var section: OrbitDetailSection = .hero
    /// The section the page is aligned on (the system scrolls to it, on its own curve).
    @State private var pagePosition: OrbitDetailSection? = .hero
    /// Bumped on every focus move inside a section (the page is held at its place again).
    @State private var anchorTick = 0
    /// The page is on screen (not under a pushed page).
    @State private var visible = false

    @State private var showStreams = false
    @State private var movieRestart = false
    @State private var seriesPlay: OrbitSeriesPlayRoute?
    @State private var postPlayPending: MetaPreview?
    @State private var postPlayRoute: TitleRoute?
    @State private var showSynopsis = false
    /// The muted trailer behind the hero, after a rest there.
    @State private var heroTrailerOn = false
    @State private var heroRestTask: Task<Void, Never>?
    /// Steven (2026-10-23): the trailer plays IN the page, full screen with its sound ("cinema"):
    /// the interface sinks away, the backdrop pushes in, the trailer fades over it (no black screen).
    @State private var cinema = false
    @State private var cinemaHint = false
    @State private var cinemaHintTask: Task<Void, Never>?
    @FocusState private var cinemaFocused: Bool
    @Namespace private var titleSpace
    /// Steven's video: most trailers open on black frames, so a cold start went black for a
    /// moment. The film's art stays over the trailer for its first seconds, then fades away.
    @State private var holdArt = false
    /// Bumped to put the page back at its top (after the trailer).
    @State private var heroPin = 0
    /// Steven: back from an actor's page the page went to its top. The card left from, and the
    /// focus held off the hero (the system's default, Lire) until it is back on it.
    @State private var lastFocus: OrbitDetailFocus?
    @State private var resumeFocus: OrbitDetailFocus?
    @State private var resuming = false
    @State private var resumeStart: TimeInterval = 0
    /// Back from a page opened from a row: the card it was opened from, the only one of the rows
    /// that can take the focus for a moment.
    @State private var returningTo: OrbitDetailFocus?
    /// Each row's scroll, kept across a push (a reference: writes never redraw the page).
    @State private var rowOffsets = OrbitRowOffsets()
    /// While one of the page's own scrolls runs (the hold below leaves it alone).
    @State private var anchoringUntil = Date.distantPast
    /// The page's scroll offset, written on every scroll frame (a box: never a page update).
    @State private var scrollBox = OrbitDetailScrollBox()
    /// TMDB's logo for the title (`OrbitMetaStore`), kept apart so the store's other titles never
    /// redraw the page.
    @State private var tmdbLogo: String?
    @State private var tmdbBackdrop: String?
    @State private var keptBackdrop: String?
    /// Per row ("cast", "saga", "similar"): bumped to bring the row back to its start.
    @State private var rowResets: [String: Int] = [:]

    init(preview: MetaPreview, platform: OrbitDetailPlatform? = nil) {
        self.preview = preview
        self.platform = platform
        _model = StateObject(wrappedValue: DetailViewModel(preview: preview))
    }

    // MARK: Derived

    private var meta: MetaDetails? { model.meta }
    private var isSeries: Bool {
        if let meta { return EpisodesSection.isSeriesLike(meta) }
        return preview.type == "series"
    }
    private var title: String { meta?.name ?? preview.name }
    private var overview: String? {
        let text: String? = meta?.description_ ?? preview.description_
        return (text ?? "").isEmpty ? nil : text
    }
    /// Steven (2026-10-25: Crystal Lake's logo in Search, none on its page): TMDB's logo first (in
    /// French when there is one, as Search and Home show it), then the add-on's.
    private var logoURL: String? { logoCandidates.first }
    /// TMDB's, then the catalog's (the card that opened the page), then the add-on page's: the
    /// add-on's is often a link that does not resolve yet for a new title.
    private var logoCandidates: [String] {
        var seen = Set<String>()
        let previewLogo: String? = preview.logo
        let metaLogo: String? = meta?.logo
        return [tmdbLogo, previewLogo, metaLogo].compactMap { $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private var posterURL: String? { meta?.poster ?? preview.poster }
    /// Steven (a page opened from À voir aussi stayed black for seconds): the add-on's details
    /// come late — TMDB's backdrop (asked for as the page opens, often already known from the row)
    /// shows at once; the first real backdrop shown is kept (no second image replacing it).
    private var realBackdrop: String? {
        let raw: String? = meta?.background ?? preview.banner ?? tmdbBackdrop
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }
    private var backdropURL: String? {
        guard let raw = quickBackdropURL else { return nil }
        return DetailBackdropURL.upgraded(raw)
    }
    /// The same art at its listed size (TMDB's 1280): it comes in a moment, the full-size one
    /// (often several megabytes — Steven: a page from À voir aussi stayed black for seconds)
    /// takes over once it has come.
    private var quickBackdropURL: String? {
        let raw: String? = keptBackdrop ?? realBackdrop ?? preview.poster
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }
    private var streamVideoId: String { meta?.id ?? preview.id }
    private var playbackMeta: PlaybackMeta {
        func nonEmpty(_ s: String?) -> String? { (s ?? "").isEmpty ? nil : s }
        return PlaybackMeta(year: nonEmpty(meta?.releaseInfo ?? preview.releaseInfo),
                            runtime: nonEmpty(meta?.runtime),
                            imdbRating: nonEmpty(meta?.imdbRating ?? preview.imdbRating),
                            ageRating: nonEmpty(meta?.ageRating),
                            genres: meta?.genres ?? preview.genres)
    }
    private var coverUp: Bool {
        // Steven: not the synopsis panel: the trailer carries on behind it, and is still there,
        // where it was, once the panel closes (it stopped and started again from the beginning).
        showStreams || seriesPlay != nil || model.trailerPlayback != nil
    }

    // MARK: Body

    var body: some View {
        let L = OrbitDetailLayout.self
        ZStack(alignment: .topLeading) {
            OrbitDetailBackground(url: backdropURL, quickURL: quickBackdropURL,
                                  trailerURL: cinema || (heroTrailerOn && section == .hero && !coverUp) ? model.trailerVideoURL : nil,
                                  zoomKey: model.trailerZoomKey,
                                  dimmed: section != .hero && !cinema,
                                  cinema: cinema,
                                  holdArt: holdArt,
                                  tint: platform?.theme.tint ?? .black,
                                  onTrailerFailure: {
                                      model.trailerFailed()
                                      if cinema { exitCinema() }
                                  },
                                  onTrailerEnded: {
                                      if cinema { exitCinema() } else { withAnimation(.easeInOut(duration: 0.6)) { heroTrailerOn = false } }
                                  })

            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: L.sectionGap) {
                    hero
                        // (The page's top margin is above it: the hero ends where it always did.)
                        .frame(height: L.heroHeight - L.pageTop, alignment: .bottomLeading)
                        // Cinema: the interface sinks a little and fades away.
                        .opacity(cinema ? 0 : 1)
                        .offset(y: cinema ? 50 : 0)
                        .id(OrbitDetailSection.hero)
                    if isSeries, let meta {
                        OrbitEpisodesSection(meta: meta,
                                             episodeRatings: model.episodeRatings,
                                             watchedEpisodeKeys: model.watchedEpisodeKeys,
                                             startSeason: model.seriesAction?.seasonNumber?.value,
                                             focus: $focus,
                                             onPlay: { episode in
                                                 seriesPlay = OrbitSeriesPlayRoute(meta: meta, episode: episode)
                                             })
                            .focusSection()
                            .id(OrbitDetailSection.episodes)
                    }
                    castSection
                    sagaSection
                    trailersSection
                    similarSection
                    aboutSection
                }
                .scrollTargetLayout()
                .padding(.bottom, 160)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Cinema: the whole page out of focus (the trailer's catcher holds it).
                .disabled(cinema)
            }
            // Fluidity (Steven, 2026-10-25: "la page de description est ultra fluide sur l'app Apple
            // TV"): built as Home now is — the system aligns the focused section under the top on
            // its own curve. Our own scrolls (the anchors, their re-tries, the holds on Left /
            // Right, the undoing of the system's nudges) and the mask over the whole page (redrawn
            // off screen on every frame of a move) are gone.
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $pagePosition, anchor: .top)
            .contentMargins(.top, L.pageTop, for: .scrollContent)
            .scrollClipDisabled()
            // Steven (the season row bounced): on a season poster the page does not scroll on its
            // own — the system nudged it a few points at each season change and the hold pulled it
            // back. The page's own moves (`anchor`, scrollTo) still place it.
            .scrollDisabled(onSeasonPoster)
            .ignoresSafeArea()
            // Steven ("le problème de coupure" on Up / Down): the system scrolled to the focus, then
            // the page scrolled again to its section — two moves. Only Menu back to the top moves the
            // page itself now; Up / Down are the system's one move, aligned on the sections.
            .onChange(of: section) { _, target in
                if target == .hero, pagePosition != .hero {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.36)) { pagePosition = .hero }
                }
            }
            }

            // Under the sections, the page fades out at the top (Steven: the trailers' captions
            // showed by the house) — a shade over it, not a mask.
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(width: OrbitHomeLayout.screenWidth, height: L.pageTop + 20)
                .opacity(section == .hero || cinema ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: section == .hero)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            // The platform's logo, top right (not in the trailer's cinema).
            if let platform, !cinema {
                OrbitDetailPlatformMark(platform: platform)
                    .transition(.opacity)
                    .zIndex(4)
            }

            if cinema {
                // The one focusable thing while the trailer plays: Menu ends it.
                Button {} label: {
                    ZStack(alignment: .bottomLeading) {
                        Color.clear
                        // Steven: the title glides here from its place in the page (one continuous
                        // move, `titleMark`), the Back hint under it; both fade after 4 s, the title
                        // staying in place (invisible) so it glides back on the way out.
                        VStack(alignment: .leading, spacing: 12) {
                            titleMark(cinema: true)
                                .opacity(cinemaHint ? 1 : 0)
                            Text(String(localized: "Appuyez sur Retour pour quitter"))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                                .opacity(cinemaHint ? 1 : 0)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 12)
                        .padding(.leading, OrbitDetailLayout.margin)
                        .padding(.bottom, 70)
                    }
                    .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(OrbitPlainStyle())
                .focused($cinemaFocused)
                .onExitCommand(perform: exitCinema)
                .transition(.opacity)
                .zIndex(5)
            }

            // A clip YouTube would not hand over: said, not a spinner that just stops.
            if let notice = model.trailerNotice {
                Label(notice, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 60)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(8)
            }

            if showSynopsis, let overview {
                OrbitSynopsisPanel(title: title, logoURL: logoURL, text: overview) {
                    withAnimation(.easeInOut(duration: 0.25)) { showSynopsis = false }
                    DispatchQueue.main.async { focus = .synopsis }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        .background(OrbitHomeLayout.background.ignoresSafeArea())
        .ignoresSafeArea()
        // Back from an actor's page the engine's own landing is the card left from (Lire else).
        .defaultFocus($focus, resumeFocus ?? .play, priority: .userInitiated)
        // Steven: a press ends the return at once (Right was pulled back to the card). The
        // clock was never installed on this page, so the press went unseen.
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        // Steven: a press while the focus still sat on the engine's card (the first one) went
        // from there (Left even left the row). During the return a press puts the card back
        // first; the next press moves from it.
        .onMoveCommand { _ in
            guard resuming, let back = resumeFocus else { return }
            // Past the first moment, or the card already focused: the press is his.
            if focus == back || ProcessInfo.processInfo.systemUptime - resumeStart > 0.3 {
                resuming = false
                resumeFocus = nil
                return
            }
            DispatchQueue.main.async { focus = back; anchorTick &+= 1 }
        }
        // Menu from a section: back to the hero; from the hero, the page leaves (system default).
        .onExitCommand(perform: section == .hero || showSynopsis ? nil : { backToHero() })
        .onChange(of: focus) { old, new in
            OrbitTrace.log("detail focus \(String(describing: old)) -> \(String(describing: new)) resuming=\(resuming) back=\(String(describing: resumeFocus)) section=\(section)")
            guard let new else { return }
            if resuming, let back = resumeFocus {
                if new == back {
                    // Back on the card left from. Not done yet (the trace, 2026-10-27: the
                    // system's own landing came 10 ms after it, on the row's first card, and won):
                    // the return lasts its moment, a press of his ends it.
                    lastFocus = new
                    enter(new.section)
                } else if !ViewerInputClock.shared.hasInput(since: resumeStart + 0.3) {
                    // The system's landing (the row's first card, Lire): the card put back at once.
                    DispatchQueue.main.async { if resuming { focus = back } }
                } else {
                    // His own move: the focus is his.
                    resuming = false
                    resumeFocus = nil
                    lastFocus = new
                    enter(new.section)
                }
                return
            }
            lastFocus = new
            // Steven: back up into the hero lands on Lire (it took the button above the card).
            if new.section == .hero, section != .hero, new != .play, !showSynopsis {
                enter(.hero)
                DispatchQueue.main.async { focus = .play }
                return
            }
            // Steven: no return to a row's start — the rows keep where they were and the focus
            // lands where the system puts it, as in Apple's app.
            enter(new.section)
        }
        .onChange(of: coverUp) { _, up in if up { stopHeroTrailer() } else if section == .hero { armHeroTrailer() } }
        .animation(.easeInOut(duration: 0.3), value: model.trailerNotice)
        .onChange(of: model.trailerVideoURL) { _, _ in if section == .hero { armHeroTrailer() } }
        .onReceive(OrbitMetaStore.shared.$metas.map { [key = OrbitMetaStore.key(preview)] in $0[key]?.logo }.removeDuplicates()) { logo in
            if tmdbLogo != logo { tmdbLogo = logo }
            if tmdbBackdrop == nil, let backdrop = OrbitMetaStore.shared.metas[OrbitMetaStore.key(preview)]?.backdrop,
               !backdrop.isEmpty {
                tmdbBackdrop = backdrop
            }
        }
        .onAppear {
            OrbitMetaStore.shared.request([preview])
            OrbitNavClock.titleOpenedAt = ProcessInfo.processInfo.systemUptime
            OrbitNavClock.titlesShown += 1
        }
        .onDisappear { OrbitNavClock.titlesShown = max(0, OrbitNavClock.titlesShown - 1) }
        .onAppear {
            OrbitTrace.log("detail appear \(preview.name) resume=\(String(describing: resumeFocus)) focus=\(String(describing: focus)) section=\(section)")
            if let back = resumeFocus {
                returningTo = back
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { returningTo = nil }
                // The engine restores late and more than once: the card is asked again a few
                // times (as the old page did), until Steven presses something.
                resuming = true
                resumeStart = ProcessInfo.processInfo.systemUptime
                // The engine lands on the row's first card once the way back has finished (about
                // half a second): asked often, so the wrong card never holds long.
                for delay in [0.0, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard resuming else { return }
                        // A press of his once the way back has settled (a third of a second): the
                        // focus is his from then on (Steven: still a wait before he could move).
                        if delay >= 0.35, ViewerInputClock.shared.hasInput(since: resumeStart + 0.3) {
                            resuming = false
                            resumeFocus = nil
                            if let focus { enter(focus.section) }
                            return
                        }
                        OrbitTrace.log("detail ask \(delay) focus=\(String(describing: focus)) -> \(back)")
                        if focus != back { focus = back }
                        anchorTick &+= 1
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                    guard resuming else { return }
                    resuming = false
                    resumeFocus = nil
                    // The page follows wherever the focus ended (it stayed on the hero's look).
                    if let focus { enter(focus.section) }
                }
            }
            visible = true
            // The trailer behind the hero is muted; only the cinema mode has sound.
            HeroTrailerAudioState.shared.setMuted(value: true)
            model.start()
            tabBarVisibility.pushImmersive()
            armHeroTrailer()
        }
        .onChange(of: qualityRequest, initial: true) { _, _ in requestQuality() }
        .onReceive(OrbitMetaStore.shared.$metas.map { [key = OrbitMetaStore.key(preview)] in $0[key]?.backdrop }.removeDuplicates()) { b in
            if tmdbBackdrop == nil, let b, !b.isEmpty { tmdbBackdrop = b }
        }
        // The first real backdrop shown stays (TMDB's, then the add-on's came and replaced it).
        .onChange(of: realBackdrop, initial: true) { _, v in
            if keptBackdrop == nil, let v { keptBackdrop = v }
        }
        // Steven (device): the house hides while the trailer plays full screen.
        .onChange(of: cinema) { _, on in OrbitHomeButtonHost.shared.hidden = on }
        .onDisappear {
            OrbitHomeButtonHost.shared.hidden = false
            // Leaving for an actor, a saga, a similar title…: where to come back.
            resumeFocus = section != .hero ? lastFocus : nil
            OrbitTrace.log("detail disappear \(preview.name) section=\(section) last=\(String(describing: lastFocus)) focus=\(String(describing: focus))")
            // Set before the way back begins (the system lands as the page comes back, before
            // its onAppear).
            returningTo = resumeFocus
            quality.stop()
            visible = false
            if cinema {
                cinema = false
                HeroTrailerAudioState.shared.setMuted(value: true)
            }
            // Left for an actor, a saga, a similar title (from a row): the page stays under it —
            // its data kept, not reloaded on the way back (Steven: back from an actor the focus
            // could not move for seconds while the whole page was loaded again). Closed (from
            // the hero), it stops as before.
            if section == .hero { model.stop() }
            tabBarVisibility.popImmersive()
            stopHeroTrailer()
        }
        // Playback: the film's source picker, a series episode's, the full-screen trailer.
        .fullScreenCover(isPresented: $showStreams, onDismiss: {
            movieRestart = false
            openPostPlayPick()
        }) {
            StreamPickerView(type: preview.type, videoId: streamVideoId, title: title,
                             poster: posterURL, synopsis: overview, meta: playbackMeta,
                             logoUrl: logoURL, backdrop: backdropURL, forceManual: false,
                             startFromBeginning: movieRestart,
                             onOpenTitle: { postPlayPending = $0 })
        }
        .fullScreenCover(item: $seriesPlay, onDismiss: openPostPlayPick) { route in
            StreamPickerView(type: route.meta.type, videoId: route.videoId, title: route.pickerTitle,
                             parentMetaId: route.meta.id,
                             season: route.season,
                             episode: route.episode,
                             episodes: route.meta.videos,
                             poster: route.meta.poster,
                             episodeStill: route.episodeStill,
                             synopsis: route.synopsis,
                             meta: playbackMeta,
                             logoUrl: logoURL,
                             backdrop: backdropURL,
                             forceManual: false,
                             startFromBeginning: route.startFromBeginning,
                             onOpenTitle: { postPlayPending = $0 })
        }
        .fullScreenCover(item: $model.trailerPlayback) { item in
            FullScreenTrailerPlayer(urlString: item.url,
                                    onPlaybackEnded: { model.trailerPlayback = nil },
                                    zoomKey: item.zoomKey,
                                    videoId: item.videoId)
                .ignoresSafeArea()
        }
        .navigationDestination(item: $postPlayRoute) { route in
            DetailView(preview: route.preview)
        }
    }

    // MARK: Focus / scroll

    private func returningElsewhere(_ target: OrbitDetailSection) -> Bool {
        guard let returningTo else { return false }
        return returningTo.section != target
    }

    /// The row of a section back to its start (its first card at the margin).
    private func resetRow(of target: OrbitDetailSection) {
        let key: String? = switch target {
        case .cast: "cast"
        case .saga: "saga"
        case .similar: "similar"
        default: nil
        }
        if let key { rowResets[key, default: 0] += 1 }
    }

    /// A section's first card (the far left of its row).
    private func firstFocus(of target: OrbitDetailSection) -> OrbitDetailFocus? {
        switch target {
        case .cast:
            return (meta?.cast ?? []).firstIndex { $0.tmdbId != nil }.map { .cast($0) }
        case .saga:
            return meta?.collectionItems.first.map { .saga($0.id) }
        case .trailers:
            return meta?.trailers.first.map { .trailerClip($0.id) }
        case .similar:
            return meta?.moreLikeThis.first.map { .similar($0.id) }
        case .about:
            return companies.first?.company.tmdbId != nil ? .company(0) : .about
        case .hero, .episodes:
            return nil
        }
    }

    private var onSeasonPoster: Bool {
        if case .season? = focus { return true }
        return false
    }

    private func anchor(_ proxy: ScrollViewProxy, _ target: OrbitDetailSection, duration: Double) {
        anchoringUntil = Date().addingTimeInterval(duration + 0.1)
        withAnimation(reduceMotion || duration == 0 ? nil : .easeInOut(duration: duration)) {
            if target == .hero {
                proxy.scrollTo(OrbitDetailSection.hero, anchor: .top)
            } else {
                // The episodes (seasons, episodes, the episode's text) are taller: higher up.
                // Steven (device, Carrie: the episodes bounced): with one season there is no season
                // row above the episodes — placed that high, their heading went under the top fade
                // and the system pulled the row back down. They rest like any section.
                let seasonCount = Set((meta?.videos ?? []).compactMap { $0.season?.value }).count
                let rest = target == .episodes && seasonCount > 1 ? OrbitDetailLayout.episodesRest : OrbitDetailLayout.sectionRest
                proxy.scrollTo(target, anchor: UnitPoint(x: 0, y: rest / OrbitHomeLayout.screenHeight))
            }
        }
    }

    private func enter(_ target: OrbitDetailSection) {
        // Moves inside the hero are left alone (re-pinning it bounced the buttons).
        guard target != section else { return }
        section = target
        if target == .hero { armHeroTrailer() } else { stopHeroTrailer() }
    }

    static let heroTitleSize = CGSize(width: 720, height: 240)
    /// The width the title's logo is drawn at (the tag above it follows it).
    @State private var taggedTitleWidth: CGFloat = 480
    static let cinemaTitleSize = CGSize(width: 340, height: 120)

    /// The title (logo or name), in the hero or in the cinema corner: ONE matched view, so going
    /// into the trailer and back it glides and resizes between the two places.
    private func titleMark(cinema corner: Bool, hugs: Bool = false) -> some View {
        let size = corner ? Self.cinemaTitleSize : Self.heroTitleSize
        // `hugs`: its own height (a tag sits on it), within the same box.
        let tagged = hugs && !corner
        return OrbitTitleMark(name: title, logo: logoURL, maxSize: tagged ? CGSize(width: size.width, height: size.height - 60) : size,
                              textSize: corner ? 40 : 76,
                              moreLogos: Array(logoCandidates.dropFirst()), hugsLogo: tagged)
            // The title's own width: the platform's tag above it is sized from it (Steven: every
            // tag fitting its title).
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { w in
                if tagged, abs(w - taggedTitleWidth) > 1 { taggedTitleWidth = w }
            }
            .frame(width: size.width, height: tagged ? nil : size.height, alignment: .bottomLeading)
            .matchedGeometryEffect(id: "orbit-detail-title", in: titleSpace, anchor: .bottomLeading)
    }

    /// What the sources are asked for (the film, or the series' next episode), once known.
    private var qualityRequest: String {
        guard let meta else { return "-" }
        if isSeries { return model.seriesAction.map { "s:\($0.videoId)" } ?? "-" }
        return "m:\(meta.id)"
    }

    private func requestQuality() {
        guard let meta else { return }
        if isSeries {
            guard let action = model.seriesAction else { return }
            quality.start(type: meta.type, videoId: action.videoId, parentMetaId: meta.id,
                          season: action.seasonNumber?.value, episode: action.episodeNumber?.value)
        } else {
            quality.start(type: preview.type, videoId: meta.id, parentMetaId: nil, season: nil, episode: nil)
        }
    }

    private func backToHero() {
        focus = .play
        enter(.hero)
    }

    /// Steven (2026-10-25): the trailer no longer starts on its own behind the hero — only the
    /// Bande-annonce button plays it (`startCinema`).
    private func armHeroTrailer() {
        heroRestTask?.cancel()
    }

    /// Bande-annonce: the trailer in the page, with its sound. Already playing muted behind the
    /// hero, it simply carries on (the sound comes in); else it fades in over the backdrop once its
    /// first frame is ready.
    private func startCinema() {
        guard model.trailerVideoURL != nil else { return }
        heroRestTask?.cancel()
        let coldStart = !heroTrailerOn
        if coldStart {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { holdArt = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeInOut(duration: 1.0)) { holdArt = false }
            }
        }
        HeroTrailerAudioState.shared.setMuted(value: false)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) {
            cinema = true
            heroTrailerOn = true
            cinemaHint = true
        }
        DispatchQueue.main.async { cinemaFocused = true }
        cinemaHintTask?.cancel()
        cinemaHintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { cinemaHint = false }
        }
    }

    /// Back (or the trailer's end): the trailer fades to the backdrop, the backdrop eases back,
    /// the interface rises again, the focus on Bande-annonce.
    private func exitCinema() {
        guard cinema else { return }
        cinemaHintTask?.cancel()
        HeroTrailerAudioState.shared.setMuted(value: true)
        holdArt = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) {
            cinema = false
            heroTrailerOn = false
            cinemaHint = false
        }
        DispatchQueue.main.async { focus = .trailer }
        // The focus coming back can nudge the page: back at its top once it has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { heroPin &+= 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { heroPin &+= 1 }
    }

    private func stopHeroTrailer() {
        heroRestTask?.cancel()
        if heroTrailerOn { withAnimation(.easeInOut(duration: 0.4)) { heroTrailerOn = false } }
    }

    private func openPostPlayPick() {
        guard let pick = postPlayPending else { return }
        postPlayPending = nil
        postPlayRoute = TitleRoute(preview: pick)
    }

    // MARK: Hero

    private var hero: some View {
        let L = OrbitDetailLayout.self
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if cinema {
                    Color.clear
                } else if let own = platform?.own {
                    // The platform's "original" tag right on top of the title (Steven: above the
                    // title's box it floated high over a wide logo).
                    VStack(alignment: .leading, spacing: 16) {
                        OrbitDetailOwnTag(own: own, series: isSeries, titleWidth: taggedTitleWidth)
                            .shadow(color: .black.opacity(0.5), radius: 6)
                        titleMark(cinema: false, hugs: true)
                    }
                } else {
                    titleMark(cinema: false)
                }
            }
            .frame(width: Self.heroTitleSize.width, height: Self.heroTitleSize.height, alignment: .bottomLeading)
            // A fixed height: the age box (taller than the text) arrives with the details and
            // made the line, so the whole block, move.
            OrbitDetailMetaLine(meta: meta, preview: preview)
                .frame(height: 44, alignment: .leading)
                .padding(.top, 34)
            // On their own line under it (beside it, they cut the genres short).
            OrbitQualityBadges(quality: quality.found)
                .frame(height: 30, alignment: .leading)
                .padding(.top, 8)
            // Steven (Apple TV style): the synopsis on the buttons' line, its arrow opens it in
            // full; Right from the last button lands on the arrow.
            // The synopsis starts at one place (about under the logo's end), whatever the buttons:
            // close to them, and still when the focused one opens to say its name.
            HStack(alignment: .center, spacing: 40) {
                actions
                    .frame(minWidth: 680, alignment: .leading)
                    .layoutPriority(1)
                if let overview {
                    // Steven: the arrow at the right margin, on the credits' edge; the text runs
                    // up to it.
                    HStack(alignment: .center, spacing: 24) {
                        Text(overview)
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(Color.white.opacity(focus == .synopsis ? 1 : 0.9))
                            .lineSpacing(4)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Steven: a touch lower, level with the buttons.
                            .offset(y: 8)
                        OrbitSynopsisArrow(focused: focus == .synopsis) {
                            withAnimation(.easeInOut(duration: 0.25)) { showSynopsis = true }
                        }
                        .focused($focus, equals: .synopsis)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 36)
            .focusSection()
            // The cast and the direction, small, bottom right.
            // Its room is held from the start (the cast arrives with the details a moment after
            // the page): else the whole block rose once they came in.
            credits
                .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .bottomTrailing)
                .padding(.top, 74)
        }
        .padding(.horizontal, L.margin)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .focusSection()
    }

    private var credits: some View {
        let cast = (meta?.cast ?? []).filter { person in
            let role = (person.role ?? "").lowercased()
            return !role.contains("director") && !role.contains("réalis")
        }
        let actors = cast.prefix(3).map(\.name)
        let directors = meta?.director ?? []
        return VStack(alignment: .trailing, spacing: 6) {
            if !actors.isEmpty {
                (Text(String(localized: "Avec ")).foregroundStyle(Color.white.opacity(0.6))
                 + Text(actors.joined(separator: ", ")).foregroundStyle(Color.white))
            }
            if !directors.isEmpty {
                (Text(String(localized: "Réalisé par ")).foregroundStyle(Color.white.opacity(0.6))
                 + Text(directors.joined(separator: ", ")).foregroundStyle(Color.white))
            }
        }
        .font(.system(size: 23, weight: .medium))
        .lineLimit(1)
        .multilineTextAlignment(.trailing)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 18) {
            primaryButton
            if !isSeries, model.hasResumableProgress {
                OrbitActionButton(icon: "arrow.counterclockwise", label: String(localized: "Recommencer"),
                                  focused: focus == .restart) {
                    movieRestart = true
                    showStreams = true
                }
                .focused($focus, equals: .restart)
            }
            if model.trailerVideoURL != nil {
                OrbitActionButton(icon: "play.rectangle.fill", label: String(localized: "Bande-annonce"),
                                  focused: focus == .trailer) {
                    startCinema()
                }
                .focused($focus, equals: .trailer)
            }
            OrbitActionButton(icon: model.isWatched ? "checkmark.circle.fill" : "checkmark.circle",
                              label: model.isWatched ? String(localized: "Vu") : String(localized: "Marquer comme vu"),
                              focused: focus == .watched) { model.toggleWatched() }
                .focused($focus, equals: .watched)
            OrbitActionButton(icon: model.isSaved ? "checkmark" : "plus",
                              label: model.isSaved ? String(localized: "Dans ma liste") : String(localized: "Ajouter à ma liste"),
                              focused: focus == .library) { model.toggleLibrary() }
                .focused($focus, equals: .library)
        }
        .animation(.easeOut(duration: 0.18), value: focus)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isSeries {
            if let action = model.seriesAction, let meta {
                OrbitPlayButton(label: model.isPlayEnabled ? OrbitDetailFormat.playLabel(action.label) : String(localized: "Lecture indisponible"),
                                focused: focus == .play, theme: platform?.theme) {
                    model.noteSeriesPlayStarted(action)
                    seriesPlay = OrbitSeriesPlayRoute(meta: meta, action: action)
                }
                .disabled(!model.isPlayEnabled)
                .focused($focus, equals: .play)
            } else {
                OrbitPlayButton(label: String(localized: "Lire"), focused: focus == .play, theme: platform?.theme) {}
                    .disabled(true)
                    .focused($focus, equals: .play)
            }
        } else {
            OrbitPlayButton(label: !model.isPlayEnabled ? String(localized: "Lecture indisponible")
                                : (model.hasResumableProgress ? String(localized: "Reprendre") : String(localized: "Lire")),
                            focused: focus == .play, theme: platform?.theme) { showStreams = true }
                .disabled(!model.isPlayEnabled)
                .focused($focus, equals: .play)
        }
    }

    // MARK: Sections

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.leading, OrbitDetailLayout.margin)
    }

    @ViewBuilder
    private var castSection: some View {
        let cast = meta?.cast ?? []
        if !cast.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                heading(String(localized: "Casting"))
                ScrollView(.horizontal, showsIndicators: false) {
                    // Every card built (a lazy row had none where the viewer came back from —
                    // Steven: back from an actor the focus fell on the first one). A cast is short.
                    HStack(alignment: .top, spacing: 34) {
                        ForEach(Array(cast.prefix(40).enumerated()), id: \.offset) { index, person in
                            if let id = person.tmdbId?.value {
                                NavigationLink(value: PersonRoute(id: id, name: person.name)) {
                                    OrbitCastCard(person: person, focused: focus == .cast(index) && (returningTo == nil || returningTo == .cast(index)))
                                }
                                .buttonStyle(OrbitPlainStyle())
                                .focused($focus, equals: .cast(index))
                            } else {
                                OrbitCastCard(person: person, focused: false)
                            }
                        }
                    }
                    .padding(.horizontal, OrbitDetailLayout.margin)
                    .padding(.vertical, 16)
                }
                .scrollClipDisabled()
                .modifier(OrbitRowMemory(key: "cast", store: rowOffsets, resetGeneration: rowResets["cast", default: 0]))
            }
            .focusSection()
            // Back from an actor the system's own landing is his card, not the row's first (the
            // trace: it went to the first, 7 ms after his).
            .defaultFocus($focus, returningTo, priority: .userInitiated)
            .id(OrbitDetailSection.cast)
        }
    }

    @ViewBuilder
    private var sagaSection: some View {
        let items = meta?.collectionItems ?? []
        if !items.isEmpty {
            let name: String? = meta?.collectionName
            VStack(alignment: .leading, spacing: 20) {
                heading((name ?? "").isEmpty ? String(localized: "La saga") : name!)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 28) {
                        ForEach(items, id: \.id) { item in
                            NavigationLink(value: TitleRoute(preview: item)) {
                                OrbitDetailLandscapeCard(item: item, focused: focus == .saga(item.id),
                                                         current: item.id == streamVideoId || item.id == preview.id)
                            }
                            .buttonStyle(OrbitPlainStyle())
                            .focused($focus, equals: .saga(item.id))
                        }
                    }
                    .padding(.horizontal, OrbitDetailLayout.margin)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
                .modifier(OrbitRowMemory(key: "saga", store: rowOffsets, resetGeneration: rowResets["saga", default: 0]))
            }
            .focusSection()
            .id(OrbitDetailSection.saga)
        }
    }

    @ViewBuilder
    private var trailersSection: some View {
        let trailers = Array((meta?.trailers ?? []).prefix(12))
        if !trailers.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                heading(String(localized: "Bandes-annonces et extras"))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 28) {
                        ForEach(trailers, id: \.id) { trailer in
                            Button { model.playTrailer(trailer) } label: {
                                OrbitTrailerCard(trailer: trailer, focused: focus == .trailerClip(trailer.id),
                                                 resolving: model.resolvingTrailerId == trailer.id)
                            }
                            .buttonStyle(OrbitPlainStyle())
                            .focused($focus, equals: .trailerClip(trailer.id))
                        }
                    }
                    .padding(.horizontal, OrbitDetailLayout.margin)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
            .focusSection()
            .id(OrbitDetailSection.trailers)
        }
    }

    @ViewBuilder
    private var similarSection: some View {
        let items = meta?.moreLikeThis ?? []
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                heading(String(localized: "À voir aussi"))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 26) {
                        ForEach(items, id: \.id) { item in
                            NavigationLink(value: TitleRoute(preview: item)) {
                                OrbitDetailPoster(item: item, focused: focus == .similar(item.id) && (returningTo == nil || returningTo == .similar(item.id)))
                            }
                            .buttonStyle(OrbitPlainStyle())
                            .focused($focus, equals: .similar(item.id))
                            .onAppear { OrbitMetaStore.shared.request([item]) }
                        }
                    }
                    .padding(.horizontal, OrbitDetailLayout.margin)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
                .modifier(OrbitRowMemory(key: "similar", store: rowOffsets, resetGeneration: rowResets["similar", default: 0]))
            }
            .focusSection()
            .defaultFocus($focus, returningTo, priority: .userInitiated)
            .id(OrbitDetailSection.similar)
        }
    }

    // MARK: About

    private var companies: [(company: MetaCompany, isNetwork: Bool)] {
        guard let meta else { return [] }
        var seen = Set<String>()
        let tagged = meta.productionCompanies.map { (company: $0, isNetwork: false) }
            + meta.networks.map { (company: $0, isNetwork: true) }
        return tagged.filter { entry in
            let logo: String? = entry.company.logo
            guard let logo, !logo.isEmpty, seen.insert(entry.company.name).inserted else { return false }
            return true
        }
        .prefix(6).map { $0 }
    }

    @ViewBuilder
    private var aboutSection: some View {
        if let meta {
            let rows = OrbitAboutRows.make(meta: meta, isSeries: isSeries)
            let logos = companies
            let warnings = model.parentalWarnings
            if !rows.isEmpty || !logos.isEmpty || !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 30) {
                    heading(String(localized: "À propos"))
                    if !logos.isEmpty {
                        HStack(spacing: 22) {
                            ForEach(Array(logos.enumerated()), id: \.offset) { index, entry in
                                if let id = entry.company.tmdbId?.value {
                                    NavigationLink(value: EntityRoute(id: id, name: entry.company.name,
                                                                      isNetwork: entry.isNetwork,
                                                                      sourceType: meta.type)) {
                                        OrbitCompanyLogo(company: entry.company, focused: focus == .company(index))
                                    }
                                    .buttonStyle(OrbitPlainStyle())
                                    .focused($focus, equals: .company(index))
                                } else {
                                    OrbitCompanyLogo(company: entry.company, focused: false)
                                }
                            }
                        }
                        .padding(.leading, OrbitDetailLayout.margin)
                    }
                    // The details block is focusable (Select does nothing) so Down reaches it.
                    Button {} label: {
                        OrbitAboutBlock(rows: rows, warnings: warnings, focused: focus == .about)
                    }
                    .buttonStyle(OrbitPlainStyle())
                    .focused($focus, equals: .about)
                    .padding(.leading, OrbitDetailLayout.margin - 24)
                }
                .focusSection()
                .id(OrbitDetailSection.about)
            }
        }
    }
}

// MARK: - Background

/// The page's one background: the backdrop (the muted trailer over it on the hero), clear on the
/// hero with a left and bottom shade for the text, dark and soft under the sections.
private struct OrbitDetailBackground: View {
    let url: String?
    /// The art's smaller copy, shown under it until the large one has come.
    var quickURL: String? = nil
    let trailerURL: String?
    let zoomKey: String
    let dimmed: Bool
    /// The trailer plays full screen with sound: the art pushes in, the shades lift.
    var cinema: Bool = false
    /// The art held over a trailer that has just started (its black opening frames).
    var holdArt: Bool = false
    /// Under the sections (black, or the platform's tint when opened from one).
    var tint: Color = .black
    let onTrailerFailure: () -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        ZStack {
            OrbitHomeLayout.background
            // Fluidity: the dimmed art is a pre-blurred copy cross-faded in (an animated live blur of
            // the whole screen made the move to the sections stutter).
            ZStack {
                if let quickURL, quickURL != url {
                    OrbitImage(url: quickURL, mode: .fill, size: CGSize(width: 1280, height: 720))
                        .frame(width: size.width, height: size.height)
                        .clipped()
                }
                OrbitSwapImage(url: url, fallback: nil, size: size)
                // Steven (device: not dark or blurred enough under the sections).
                OrbitPreBlurred(url: url, radius: 44)
                    .opacity(dimmed ? 1 : 0)
            }
            .scaleEffect(dimmed ? 1.06 : (cinema ? 1.05 : 1))
            // Steven: the bottom of the art melts into a blur (Apple TV style), under the
            // synopsis and the credits. On the still art only (a live blur over the trailer costs
            // the Apple TV too much): the trailer covers it as it fades in, and it is back when
            // the art returns. Gone in cinema and under the sections.
            // A little darkened and desaturated, so a bright art (Pixar) melts into the shade
            // instead of smearing its colours.
            OrbitPreBlurred(url: url, radius: 40)
                .saturation(0.75)
                .overlay(Color.black.opacity(0.3))
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0.7),
                    .init(color: .black.opacity(0.7), location: 0.86),
                    .init(color: .black, location: 0.97),
                ], startPoint: .top, endPoint: .bottom))
                .opacity(cinema || dimmed ? 0 : 1)
                .allowsHitTesting(false)
            if let trailerURL {
                TrailerHeroPlayer(urlString: trailerURL,
                                  onFailure: { _ in onTrailerFailure() },
                                  zoomKey: zoomKey,
                                  loops: false,
                                  onPlaybackEnded: onTrailerEnded,
                                  cornerRadius: 0,
                                  uncropped: cinema)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
            // The art held over a trailer just started. Steven (a ghost frame of the trailer, then
            // the page, then the trailer): always there, already loaded — it no longer appears a
            // moment after the trailer's first frame.
            OrbitSwapImage(url: url, fallback: nil, size: size)
                .scaleEffect(cinema ? 1.05 : 1)
                // (Not tied to the trailer's arrival: that came in the same animated change, so the art
                // faded in with the trailer and its first frames showed through.)
                .opacity(holdArt ? 1 : 0)
                .allowsHitTesting(false)
            // The hero's shades: the left for the logo and actions, the bottom for the synopsis.
            Group {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.78), location: 0),
                    .init(color: .black.opacity(0.35), location: 0.45),
                    .init(color: .clear, location: 0.7),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.75), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            // Cinema: only a light bottom shade stays (for the title and the hint).
            .opacity(cinema ? 0.35 : 1)
            // Under the sections: dark enough for white text on any art.
            tint.opacity(dimmed ? 0.74 : 0)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.easeInOut(duration: 0.45), value: dimmed)
        .animation(.easeInOut(duration: 0.8), value: cinema)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Meta line

/// "2001 · 1 h 32 · Animation, Comédie · [U] · ★ 8,1"
private struct OrbitDetailMetaLine: View {
    let meta: MetaDetails?
    let preview: MetaPreview

    var body: some View {
        let year = OrbitDetailFormat.year(meta?.releaseInfo ?? preview.releaseInfo)
        let runtime = OrbitDetailFormat.runtime(meta?.runtime)
        let genres = Array((meta?.genres ?? preview.genres).prefix(2))
        let age: String? = meta?.ageRating
        let rating = OrbitDetailFormat.rating(meta?.imdbRating ?? preview.imdbRating)
        var parts: [String] = []
        if let year { parts.append(year) }
        if let runtime { parts.append(runtime) }
        if !genres.isEmpty { parts.append(genres.joined(separator: ", ")) }
        return HStack(spacing: 14) {
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
            }
            if let age, !age.isEmpty {
                Text(age)
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
            }
            if let rating {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").foregroundStyle(Color(red: 1, green: 0.78, blue: 0.2))
                    Text(rating)
                }
            }
        }
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.92))
        .lineLimit(1)
    }
}

enum OrbitDetailFormat {
    /// "2001-11-01" → "2001"; "2019–2023" and "2019" stay as they are.
    static func year(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.count == 10, raw.dropFirst(4).first == "-", Int(raw.prefix(4)) != nil { return String(raw.prefix(4)) }
        return raw
    }

    /// "92m", "92 min", "1h 32m" → "1 h 32"; under an hour, "45 min".
    static func runtime(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let numbers = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard !numbers.isEmpty else { return raw }
        let minutes: Int
        if raw.lowercased().contains("h"), numbers.count >= 2 {
            minutes = numbers[0] * 60 + numbers[1]
        } else if raw.lowercased().contains("h") {
            minutes = numbers[0] * 60
        } else {
            minutes = numbers[0]
        }
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) min" }
        let m = minutes % 60
        return m == 0 ? "\(minutes / 60) h" : String(format: "%d h %02d", minutes / 60, m)
    }

    /// "8.1" → "8,1" (the viewer's decimal separator).
    static func rating(_ raw: String?) -> String? {
        guard let raw, let value = Double(raw.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value))
    }

    /// "US" → "États-Unis"; several codes joined.
    static func country(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let names = raw.split(whereSeparator: { $0 == "," || $0 == "/" }).map { part -> String in
            let code = part.trimmingCharacters(in: .whitespaces)
            if code.count == 2, let name = Locale.current.localizedString(forRegionCode: code.uppercased()) { return name }
            return code
        }
        return names.joined(separator: ", ")
    }

    /// "en" → "Anglais".
    static func language(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let code = raw.trimmingCharacters(in: .whitespaces)
        if code.count <= 3, let name = Locale.current.localizedString(forLanguageCode: code.lowercased()) {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return code
    }
}

// MARK: - About

struct OrbitAboutRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

enum OrbitAboutRows {
    static func make(meta: MetaDetails, isSeries: Bool) -> [OrbitAboutRow] {
        var rows: [OrbitAboutRow] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append(OrbitAboutRow(label: label, value: value)) }
        }
        add(String(localized: "Réalisation"), meta.director.joined(separator: ", "))
        add(String(localized: "Scénario"), meta.writer.joined(separator: ", "))
        add(String(localized: "Studios"), meta.productionCompanies.map(\.name).joined(separator: ", "))
        if isSeries { add(String(localized: "Diffuseur"), meta.networks.map(\.name).joined(separator: ", ")) }
        let country: String? = meta.country
        add(String(localized: "Pays"), OrbitDetailFormat.country(country))
        let language: String? = meta.language
        add(String(localized: "Langue originale"), OrbitDetailFormat.language(language))
        if isSeries {
            let status: String? = meta.status
            add(String(localized: "Statut"), DetailStatusText.localized(status))
        }
        let awards: String? = meta.awards
        add(String(localized: "Récompenses"), awards)
        let ratings = meta.externalRatings
        if !ratings.isEmpty {
            add(String(localized: "Notes"), ratings.map { "\($0.source) \(OrbitDetailFormat.rating(String($0.value)) ?? String($0.value))" }
                .joined(separator: "   ·   "))
        }
        return rows
    }
}

private struct OrbitAboutBlock: View {
    let rows: [OrbitAboutRow]
    let warnings: [ParentalWarning]
    let focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 30) {
                    Text(row.label)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 260, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: 1200, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !warnings.isEmpty {
                HStack(alignment: .top, spacing: 30) {
                    Text(String(localized: "Contrôle parental"))
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 260, alignment: .leading)
                    HStack(spacing: 26) {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Self.color(warning.severity))
                                    .frame(width: 12, height: 12)
                                Text(warning.label)
                                    .foregroundStyle(Color.white)
                                Text(warning.severity.lowercased())
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }
                        }
                    }
                    .font(.system(size: 24, weight: .medium))
                }
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(focused ? 0.1 : 0)))
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    static func color(_ severity: String) -> Color {
        let s = severity.lowercased()
        if s.contains("severe") || s.contains("sév") || s.contains("élev") { return Color(red: 0.95, green: 0.3, blue: 0.3) }
        if s.contains("moder") || s.contains("modér") { return Color.orange }
        return Color.yellow
    }
}

private struct OrbitCompanyLogo: View {
    let company: MetaCompany
    let focused: Bool

    var body: some View {
        let logo: String? = company.logo
        // Steven's video: white silhouettes turned logos with their own backdrop (ABC's disc)
        // into white blobs. The logos in their colours, on a light chip.
        CachedAsyncImage(string: logo, contentMode: .fit, decodeSize: .points(width: 200, height: 70))
            .frame(width: 170, height: 56)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(focused ? 1 : 0.88)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 0.9 : 0), lineWidth: 3))
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.16), value: focused)
            .accessibilityLabel(company.name)
    }
}

// MARK: - Buttons

/// Lire / Reprendre: a white capsule with black text (legible at rest and focused).
private struct OrbitPlayButton: View {
    let label: String
    let focused: Bool
    /// The platform's Lecture button (its colour and shape), else Orbit's white capsule.
    var theme: OrbitPlatformTheme? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                Text(label).lineLimit(1)
            }
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(theme?.playText ?? Color.black)
            .padding(.horizontal, 44)
            .frame(height: 84)
            .background {
                if let radius = theme?.playRadius {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill((theme?.playFill ?? .white).opacity(focused ? 1 : 0.86))
                } else {
                    Capsule().fill((theme?.playFill ?? .white).opacity(focused ? 1 : 0.86))
                }
            }
            .overlay {
                // A coloured button shows its focus with a white rim.
                if let theme, theme.playFill != .white, focused {
                    if let radius = theme.playRadius {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white, lineWidth: 3)
                    } else {
                        Capsule().strokeBorder(Color.white, lineWidth: 3)
                    }
                }
            }
            .scaleEffect(focused ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 18, y: 8)
            .animation(.easeOut(duration: 0.16), value: focused)
        }
        .buttonStyle(OrbitPlainStyle())
    }
}

/// The detail page's scroll offset (see `scrollBox`).
final class OrbitDetailScrollBox {
    var y: CGFloat = 0
}

/// A round icon that widens into a capsule with its name when focused.
private struct OrbitActionButton: View {
    let icon: String
    let label: String
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: focused ? 12 : 0) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                // Steven (device, three times: the words came in from the side): they are never
                // inserted any more — always laid out, in a box that opens with the pill from the
                // icon's side, so they are uncovered where they stay instead of travelling in.
                Text(label)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: focused ? nil : 0, alignment: .leading)
                    .clipped()
                    .opacity(focused ? 1 : 0)
                    .animation(focused ? .easeOut(duration: 0.16).delay(0.06) : .easeOut(duration: 0.08), value: focused)
            }
            .foregroundStyle(focused ? Color.black : Color.white)
            .padding(.horizontal, focused ? 30 : 0)
            .frame(minWidth: 84, minHeight: 84)
            .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.2)))
            .scaleEffect(focused ? 1.04 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 16, y: 8)
        }
        .buttonStyle(OrbitPlainStyle())
        .accessibilityLabel(label)
    }
}

/// No system platter: each element draws its own focus.
struct OrbitPlainStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Row memory

/// Where each row was scrolled, by row (a reference box: written on every scroll frame, never a
/// page update).
final class OrbitRowOffsets {
    var x: [String: CGFloat] = [:]
}

/// Steven: back from an actor's page the row came back scrolled to its start, so the focus first
/// landed on the first card (and stayed there on a quick press). The row now returns where it was
/// at once, its card already under the focus.
private struct OrbitRowMemory: ViewModifier {
    let key: String
    let store: OrbitRowOffsets
    /// Bumped when the focus enters the row on its first card: the row goes back to its start
    /// (Steven: the cast row stayed scrolled, its first card not at the margin).
    var resetGeneration = 0
    @State private var position = ScrollPosition(edge: .leading)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onChange(of: resetGeneration) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .leading) }
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in
                store.x[key] = x
            }
            // The row where it was, so the card left from exists again (a lazy row rebuilt at
            // its start had no card there: the focus fell on the first one — Steven's video).
            .onAppear {
                if let x = store.x[key], x > 1 {
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) { position.scrollTo(x: x) }
                }
            }
    }
}

// MARK: - Synopsis

/// The round arrow after the synopsis on the buttons' line: opens it in full.
private struct OrbitSynopsisArrow: View {
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(focused ? Color.black : Color.white)
                .frame(width: 104, height: 68)
                .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.2)))
                .scaleEffect(focused ? 1.06 : 1)
                .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 16, y: 8)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
        .buttonStyle(OrbitPlainStyle())
        .accessibilityLabel(String(localized: "Synopsis"))
    }
}

/// The full synopsis, over the page. Menu (or Select) closes it.
private struct OrbitSynopsisPanel: View {
    let title: String
    let logoURL: String?
    let text: String
    let onClose: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            Button(action: onClose) {
                VStack(alignment: .leading, spacing: 30) {
                    OrbitTitleMark(name: title, logo: logoURL, maxSize: CGSize(width: 500, height: 160), textSize: 54)
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(text)
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Color.white)
                            .lineSpacing(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 520)
                }
                .padding(60)
                .frame(width: 1240, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.ultraThinMaterial))
                .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color.black.opacity(0.4)))
            }
            .buttonStyle(OrbitPlainStyle())
            .focused($focused)
            .onExitCommand(perform: onClose)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

// MARK: - Cards

private struct OrbitCastCard: View {
    let person: MetaPerson
    let focused: Bool

    var body: some View {
        let photo: String? = person.photo
        let role: String? = person.role
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.12))
                if let photo, !photo.isEmpty {
                    CachedAsyncImage(string: photo, decodeSize: .points(width: 170, height: 170))
                        .clipShape(Circle())
                } else {
                    Text(String(person.name.prefix(1)))
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(width: 170, height: 170)
            .overlay(Circle().strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 5))
            // Steven (lag in the cast row): no shadow animated on every step — the lift alone.
            .compositingGroup()
            .scaleEffect(focused ? 1.1 : 1)
            VStack(spacing: 4) {
                Text(person.name)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.white)
                if let role, !role.isEmpty {
                    Text(role.replacingOccurrences(of: " (voice)", with: String(localized: " (voix)")))
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .lineLimit(1)
            .frame(width: 200)
        }
        .animation(.easeOut(duration: 0.16), value: focused)
    }
}

/// The saga's films: 16:9 art with the title's logo, its name and year under it.
private struct OrbitDetailLandscapeCard: View {
    let item: MetaPreview
    let focused: Bool
    let current: Bool

    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let size = CGSize(width: 440, height: 248)
        let info = OrbitInfo.make(item, meta: metaStore.meta(for: item))
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Color(white: 0.12)
                OrbitImage(url: InlineTrailerCard.landscapeArtworkURL(item) ?? metaStore.meta(for: item)?.backdrop,
                           fallback: item.poster, size: size, placeholder: item.poster)
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                OrbitTitleMark(name: item.name, logo: info.logo,
                               maxSize: CGSize(width: size.width * 0.6, height: size.height * 0.32), textSize: 26)
                    .padding(16)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : (current ? 0.5 : 0)), lineWidth: focused ? 5 : 3))
            .scaleEffect(focused ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0.2), radius: 18, y: 10)
            HStack(spacing: 8) {
                Text(item.name).lineLimit(1)
                if let year = OrbitDetailFormat.year(item.releaseInfo) {
                    Text("· \(year)").foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: size.width, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.16), value: focused)
        .onAppear { metaStore.request([item]) }
    }
}

private struct OrbitDetailPoster: View {
    let item: MetaPreview
    let focused: Bool

    var body: some View {
        let size = CGSize(width: 200, height: 300)
        ZStack {
            Color(white: 0.12)
            OrbitImage(url: item.poster, fallback: item.rawPosterUrl, size: size)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4))
        .scaleEffect(focused ? 1.08 : 1)
        .shadow(color: .black.opacity(focused ? 0.55 : 0.2), radius: 16, y: 8)
        .animation(.easeOut(duration: 0.16), value: focused)
        .accessibilityLabel(item.name)
    }
}

private struct OrbitTrailerCard: View {
    let trailer: MetaTrailer
    let focused: Bool
    let resolving: Bool

    var body: some View {
        let size = CGSize(width: 400, height: 225)
        let name: String = trailer.displayName ?? trailer.name
        let date: String? = trailer.publishedAt
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color(white: 0.12)
                OrbitImage(url: trailer.thumbnailURLString, size: size)
                if resolving {
                    ProgressView()
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(22)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .opacity(focused ? 1 : 0.7)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 5))
            .scaleEffect(focused ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0.2), radius: 18, y: 10)
            Text(name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .frame(width: size.width, alignment: .leading)
            Text([OrbitDetailFormat.trailerKind(trailer.type), date.flatMap { OrbitDetailFormat.year(String($0.prefix(4))) }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .animation(.easeOut(duration: 0.16), value: focused)
    }
}

extension OrbitDetailFormat {
    /// The series' Play label from the shared code ("Play S1E1", "Resume S2E4") in French.
    static func playLabel(_ raw: String) -> String {
        for (english, french) in [("Play ", "Lire "), ("Resume ", "Reprendre "), ("Continue ", "Continuer "),
                                  ("Start ", "Commencer "), ("Watch ", "Regarder ")] where raw.hasPrefix(english) {
            return french + raw.dropFirst(english.count)
        }
        switch raw {
        case "Play": return String(localized: "Lire")
        case "Resume": return String(localized: "Reprendre")
        default: return raw
        }
    }

    static func trailerKind(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "trailer": return String(localized: "Bande-annonce")
        case "teaser": return String(localized: "Teaser")
        case "clip": return String(localized: "Extrait")
        case "featurette": return String(localized: "Making-of")
        case "behind the scenes": return String(localized: "Coulisses")
        case "bloopers": return String(localized: "Bêtisier")
        default: return raw.isEmpty ? nil : raw
        }
    }
}

// MARK: - Series play route

/// A series episode to play: the picker's inputs (as the legacy page's route).
struct OrbitSeriesPlayRoute: Identifiable {
    let meta: MetaDetails
    let videoId: String
    let season: Int?
    let episode: Int?
    let pickerTitle: String
    let episodeStill: String?
    let synopsis: String?
    var startFromBeginning: Bool = false
    var id: String { videoId }

    /// The hero's Play: the series' next episode (or the resumed one).
    init(meta: MetaDetails, action: SeriesPrimaryAction) {
        self.meta = meta
        videoId = action.videoId
        season = action.seasonNumber?.value
        episode = action.episodeNumber?.value
        let video = meta.videos.first { $0.season?.value == action.seasonNumber?.value && $0.episode?.value == action.episodeNumber?.value }
        let name: String? = action.episodeTitle
        if let s = season, let e = episode {
            pickerTitle = (name ?? "").isEmpty ? "S\(s)E\(e)" : "S\(s)E\(e) \u{00B7} \(name!)"
        } else {
            pickerTitle = action.label
        }
        let still: String? = action.episodeThumbnail
        let videoStill: String? = video?.thumbnail
        episodeStill = !(still ?? "").isEmpty ? still : ((videoStill ?? "").isEmpty ? nil : videoStill)
        let overview: String? = video?.overview
        let description: String? = meta.description_
        synopsis = !(overview ?? "").isEmpty ? overview : description
    }

    /// An episode picked in the Episodes section.
    init(meta: MetaDetails, episode video: MetaVideo) {
        self.meta = meta
        season = video.season?.value
        episode = video.episode?.value
        if let s = season, let e = episode {
            videoId = "\(meta.id):\(s):\(e)"
            pickerTitle = "S\(s)E\(e) \u{00B7} \(video.title)"
        } else {
            videoId = video.id
            pickerTitle = video.title
        }
        let still: String? = video.thumbnail
        episodeStill = (still ?? "").isEmpty ? nil : still
        let overview: String? = video.overview
        let description: String? = meta.description_
        synopsis = !(overview ?? "").isEmpty ? overview : description
    }
}
