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
//    liste — the focused one says its name), and on the right the synopsis (Select opens it in
//    full in a panel) with "Avec … · Réalisé par …". The muted trailer plays behind it after a
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
    static let heroHeight: CGFloat = 990
    static let sectionGap: CGFloat = 70
    /// Where a section's top rests on screen when the focus is in it.
    static let sectionRest: CGFloat = 90
}

/// Every route to a title opens the Orbit page (Steven: the old page is retired).
struct DetailView: View {
    let preview: MetaPreview

    var body: some View {
        OrbitDetailView(preview: preview)
    }
}

struct OrbitDetailView: View {
    let preview: MetaPreview

    @StateObject private var model: DetailViewModel
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("detail_trailer_background") private var backgroundTrailerEnabled = true

    @FocusState private var focus: OrbitDetailFocus?
    @State private var section: OrbitDetailSection = .hero
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

    init(preview: MetaPreview) {
        self.preview = preview
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
    private var logoURL: String? {
        let logo: String? = meta?.logo ?? preview.logo
        return (logo ?? "").isEmpty ? nil : logo
    }
    private var posterURL: String? { meta?.poster ?? preview.poster }
    private var backdropURL: String? {
        let raw: String? = meta?.background ?? preview.banner ?? preview.poster
        guard let raw, !raw.isEmpty else { return nil }
        return DetailBackdropURL.upgraded(raw)
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
        showStreams || seriesPlay != nil || model.trailerPlayback != nil || showSynopsis
    }

    // MARK: Body

    var body: some View {
        let L = OrbitDetailLayout.self
        ZStack(alignment: .topLeading) {
            OrbitDetailBackground(url: backdropURL,
                                  trailerURL: heroTrailerOn && section == .hero && !coverUp ? model.trailerVideoURL : nil,
                                  zoomKey: model.trailerZoomKey,
                                  dimmed: section != .hero,
                                  onTrailerFailure: { model.trailerFailed() },
                                  onTrailerEnded: { withAnimation(.easeInOut(duration: 0.6)) { heroTrailerOn = false } })

            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: L.sectionGap) {
                    hero
                        .frame(height: L.heroHeight, alignment: .bottomLeading)
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
                .padding(.bottom, 160)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
            .ignoresSafeArea()
            // The section the focus entered comes to the top on one curve; the hero, to the top.
            .onChange(of: section) { _, target in anchor(proxy, target, duration: 0.4) }
            // Steven: Left / Right inside a section let the system nudge the page ("ça se
            // replace"); each move inside a section holds it at its place again.
            .onChange(of: anchorTick) { _, _ in anchor(proxy, section, duration: 0.22) }
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
        .defaultFocus($focus, .play, priority: .userInitiated)
        // Menu from a section: back to the hero; from the hero, the page leaves (system default).
        .onExitCommand(perform: section == .hero || showSynopsis ? nil : { backToHero() })
        .onChange(of: focus) { old, new in
            if let new {
                enter(new.section)
            }
        }
        .onChange(of: coverUp) { _, up in if up { stopHeroTrailer() } else if section == .hero { armHeroTrailer() } }
        .onChange(of: model.trailerVideoURL) { _, _ in if section == .hero { armHeroTrailer() } }
        .onAppear {
            visible = true
            model.start()
            tabBarVisibility.pushImmersive()
            armHeroTrailer()
        }
        .onDisappear {
            visible = false
            model.stop()
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
                             logoUrl: logoURL, forceManual: false,
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

    private func anchor(_ proxy: ScrollViewProxy, _ target: OrbitDetailSection, duration: Double) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: duration)) {
            if target == .hero {
                proxy.scrollTo(OrbitDetailSection.hero, anchor: .top)
            } else {
                proxy.scrollTo(target, anchor: UnitPoint(x: 0, y: OrbitDetailLayout.sectionRest / OrbitHomeLayout.screenHeight))
            }
        }
    }

    private func enter(_ target: OrbitDetailSection) {
        guard target != section else { anchorTick &+= 1; return }
        section = target
        if target == .hero { armHeroTrailer() } else { stopHeroTrailer() }
    }

    private func backToHero() {
        focus = .play
        enter(.hero)
    }

    private func armHeroTrailer() {
        heroRestTask?.cancel()
        guard backgroundTrailerEnabled, model.trailerVideoURL != nil, !coverUp else { return }
        heroRestTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, section == .hero, !coverUp else { return }
            withAnimation(.easeInOut(duration: 0.8)) { heroTrailerOn = true }
        }
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
        return HStack(alignment: .bottom, spacing: 60) {
            VStack(alignment: .leading, spacing: 0) {
                OrbitTitleMark(name: title, logo: logoURL,
                               maxSize: CGSize(width: 720, height: 240), textSize: 76)
                OrbitDetailMetaLine(meta: meta, preview: preview)
                    .padding(.top, 34)
                actions
                    .padding(.top, 36)
            }
            .frame(width: 900, alignment: .bottomLeading)

            VStack(alignment: .leading, spacing: 22) {
                if let overview {
                    // Steven: "Plus" was hard to reach (the teaser sat above the buttons' line,
                    // so Right from the last button found nothing). Its own focus section
                    // catches Right from any button.
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showSynopsis = true }
                    } label: {
                        OrbitSynopsisTeaser(text: overview, focused: focus == .synopsis)
                    }
                    .buttonStyle(OrbitPlainStyle())
                    .focused($focus, equals: .synopsis)
                }
                credits
            }
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .focusSection()
        }
        .padding(.horizontal, L.margin)
        .padding(.bottom, 70)
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
        return VStack(alignment: .leading, spacing: 6) {
            if !actors.isEmpty {
                (Text(String(localized: "Avec ")).foregroundStyle(Color.white.opacity(0.6))
                 + Text(actors.joined(separator: ", ")).foregroundStyle(Color.white))
            }
            if !directors.isEmpty {
                (Text(String(localized: "Réalisé par ")).foregroundStyle(Color.white.opacity(0.6))
                 + Text(directors.joined(separator: ", ")).foregroundStyle(Color.white))
            }
        }
        .font(.system(size: 25, weight: .medium))
        .lineLimit(1)
        .padding(.leading, 18)
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
                    if let url = model.trailerVideoURL {
                        model.trailerPlayback = TrailerPlaybackItem(id: "hero-trailer", url: url, title: title,
                                                                    zoomKey: model.trailerZoomKey,
                                                                    videoId: model.trailerVideoId)
                    }
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
                                focused: focus == .play) {
                    model.noteSeriesPlayStarted(action)
                    seriesPlay = OrbitSeriesPlayRoute(meta: meta, action: action)
                }
                .disabled(!model.isPlayEnabled)
                .focused($focus, equals: .play)
            } else {
                OrbitPlayButton(label: String(localized: "Lire"), focused: focus == .play) {}
                    .disabled(true)
                    .focused($focus, equals: .play)
            }
        } else {
            OrbitPlayButton(label: !model.isPlayEnabled ? String(localized: "Lecture indisponible")
                                : (model.hasResumableProgress ? String(localized: "Reprendre") : String(localized: "Lire")),
                            focused: focus == .play) { showStreams = true }
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
                    LazyHStack(alignment: .top, spacing: 34) {
                        ForEach(Array(cast.enumerated()), id: \.offset) { index, person in
                            if let id = person.tmdbId?.value {
                                NavigationLink(value: PersonRoute(id: id, name: person.name)) {
                                    OrbitCastCard(person: person, focused: focus == .cast(index))
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
            }
            .focusSection()
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
                                OrbitDetailPoster(item: item, focused: focus == .similar(item.id))
                            }
                            .buttonStyle(OrbitPlainStyle())
                            .focused($focus, equals: .similar(item.id))
                        }
                    }
                    .padding(.horizontal, OrbitDetailLayout.margin)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
            .focusSection()
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
    let trailerURL: String?
    let zoomKey: String
    let dimmed: Bool
    let onTrailerFailure: () -> Void
    let onTrailerEnded: () -> Void

    var body: some View {
        let size = CGSize(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        ZStack {
            OrbitHomeLayout.background
            OrbitSwapImage(url: url, fallback: nil, size: size)
                .blur(radius: dimmed ? 26 : 0, opaque: true)
                .scaleEffect(dimmed ? 1.06 : 1)
            if let trailerURL {
                TrailerHeroPlayer(urlString: trailerURL,
                                  onFailure: { _ in onTrailerFailure() },
                                  zoomKey: zoomKey,
                                  loops: false,
                                  onPlaybackEnded: onTrailerEnded,
                                  cornerRadius: 0)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
            // The hero's shades: the left for the logo and actions, the bottom for the synopsis.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.78), location: 0),
                .init(color: .black.opacity(0.35), location: 0.45),
                .init(color: .clear, location: 0.7),
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.35),
                .init(color: .black.opacity(0.75), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // Under the sections: dark enough for white text on any art.
            Color.black.opacity(dimmed ? 0.62 : 0)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.easeInOut(duration: 0.45), value: dimmed)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                Text(label).lineLimit(1)
            }
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 44)
            .frame(height: 84)
            .background(Capsule().fill(Color.white.opacity(focused ? 1 : 0.86)))
            .scaleEffect(focused ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 18, y: 8)
            .animation(.easeOut(duration: 0.16), value: focused)
        }
        .buttonStyle(OrbitPlainStyle())
    }
}

/// A round icon that widens into a capsule with its name when focused.
private struct OrbitActionButton: View {
    let icon: String
    let label: String
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                if focused {
                    Text(label)
                        .font(.system(size: 28, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
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

// MARK: - Synopsis

private struct OrbitSynopsisTeaser: View {
    let text: String
    let focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.94))
                .lineSpacing(5)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Text(String(localized: "Plus"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.white.opacity(focused ? 1 : 0.6))
        }
        .padding(18)
        .frame(maxWidth: 820, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(focused ? 0.14 : 0)))
        .scaleEffect(focused ? 1.02 : 1, anchor: .leading)
        .animation(.easeOut(duration: 0.18), value: focused)
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
            .scaleEffect(focused ? 1.1 : 1)
            .shadow(color: .black.opacity(focused ? 0.5 : 0.2), radius: 16, y: 8)
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
