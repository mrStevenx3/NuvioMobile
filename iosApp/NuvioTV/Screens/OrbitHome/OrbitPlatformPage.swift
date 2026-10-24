import Combine
import SharedCore
import SwiftUI

// Orbit Plateformes — inside a platform (Steven, 2026-10-24): the page a platform (or a studio)
// folder opens on, rebuilt from scratch in the Orbit Home style. One page for every platform, each
// dressed in its own colours:
//
//  - The intro: the platform's logo large on a screen tinted with its colour, then gliding to the
//    top-right corner while the page appears (an app opening on Apple TV). Any press skips it.
//  - Top-left, the platform's own bar: Search (inside the platform only), Films, Séries.
//  - The hero, Home's own card: the platform's featured titles (Left / Right), the trailer after
//    a rest, "Voir la fiche".
//  - The rows, Home's own rows: the folder's catalogs (Nouveautés, Top 10 with the ranks…), then
//    the platform's franchises (Disney+: Marvel, Star Wars, Pixar) and its genres (TMDB, only what
//    is on the platform in the viewer's region).
//  - The background takes the platform's colour (Netflix red, Disney+ and Prime blue…).
//
// The data is the folder's (`FolderDetailViewModel`, the collection's catalogs); everything drawn
// is new. The page is the single focusable canvas of Orbit Home (one stop, the page moves).

struct OrbitPlatformPage: View {
    let route: FolderRoute
    let push: (TitleRoute) -> Void

    @StateObject private var model: FolderDetailViewModel
    @StateObject private var extras = OrbitPlatformExtrasModel()
    @StateObject private var trailer = InlineTrailerCardModel()
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OrbitHomeSetting.trailersKey) private var trailersOn = true

    @State private var typeFilter: String? = "movie"
    @State private var current = 0
    @State private var leads: [String: Int] = [:]
    @State private var heroIndex = 0
    @FocusState private var canvasFocused: Bool
    @State private var motion = OrbitHomeMotion()
    @State private var trailerKey: String?
    @State private var search: OrbitPlatformSearchModel?

    init(route: FolderRoute, push: @escaping (TitleRoute) -> Void) {
        self.route = route
        self.push = push
        _model = StateObject(wrappedValue: FolderDetailViewModel(route: route))
    }

    private enum Section: Equatable {
        case hero
        case row(OrbitRow)

        var id: String {
            switch self {
            case .hero: return "hero"
            case .row(let row): return row.id
            }
        }
    }

    // MARK: Data

    private var series: Bool { typeFilter == "series" }
    private var brand: Color { OrbitPlatformBrand.color(title: model.folderTitle) }

    /// The folder's catalogs of the current type, loaded ones only.
    private var catalogRows: [OrbitRow] {
        CollectionTypeFilter.rows(model.stripRows, filter: typeFilter).compactMap { row in
            guard row.status == .loaded, let items = row.section?.items, !items.isEmpty else { return nil }
            var seen = Set<String>()
            let cards = items.map(OrbitCard.catalog).filter { seen.insert($0.id).inserted }
            let heading = row.heading.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let ranked = heading.contains("top 10") || heading.contains("top10")
            return OrbitRow(id: row.id, title: row.heading, cards: cards, ranked: ranked)
        }
    }

    private var rows: [OrbitRow] {
        catalogRows + (series ? extras.seriesRows : extras.movieRows)
    }

    /// The featured titles: the first row's first titles that have a backdrop.
    private var heroItems: [MetaPreview] {
        guard let first = rows.first else { return [] }
        let withArt = first.cards.map(\.preview).filter { item in
            let banner: String? = item.banner
            return !(banner ?? "").isEmpty
        }
        return Array((withArt.isEmpty ? first.cards.map(\.preview) : withArt).prefix(8))
    }

    private var sections: [Section] {
        var out: [Section] = []
        if !heroItems.isEmpty { out.append(.hero) }
        out.append(contentsOf: rows.map(Section.row))
        return out
    }

    // MARK: Geometry (Orbit Home's)

    private func anchors(_ sections: [Section]) -> [CGFloat] {
        let L = OrbitHomeLayout.self
        var y: CGFloat = 0
        var out: [CGFloat] = []
        for section in sections {
            out.append(y)
            switch section {
            case .hero: y += L.heroPitch
            case .row: y += L.rowPitch
            }
        }
        return out
    }

    private func screenLine(_ section: Section) -> CGFloat {
        switch section {
        case .hero: return OrbitHomeLayout.heroTop
        case .row: return OrbitHomeLayout.rowAnchor
        }
    }

    // MARK: Body

    var body: some View {
        let sections = sections
        let anchors = anchors(sections)
        let index = min(current, max(0, sections.count - 1))
        let scroll = sections.isEmpty ? 0 : screenLine(sections[index]) - anchors[index]
        let window = max(0, index - 1)...max(max(0, index - 1), min(sections.count - 1, index + 2))
        let heroItem = heroItems.isEmpty ? nil : heroItems[heroIndex % heroItems.count]

        ZStack(alignment: .topLeading) {
            OrbitPlatformBackground(brand: brand)

            ZStack(alignment: .topLeading) {
                if !sections.isEmpty {
                    ForEach(Array(zip(window, sections[window])), id: \.1.id) { i, section in
                        sectionView(section, isCurrent: i == index, heroItem: heroItem)
                            .offset(y: anchors[i])
                            .opacity(i < index ? 0 : 1)
                            .transition(.identity)
                    }
                }
            }
            .offset(y: scroll)

            if sections.isEmpty, model.isLoading {
                ProgressView()
                    .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
            }

            // The page's one focusable stop, under the bar's band.
            Button(action: select) {
                Color.clear
                    .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight - 110)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrbitPlatformCanvasStyle())
            .focused($canvasFocused)
            .onMoveCommand(perform: move)
            .onExitCommand(perform: exitAction(index: index))
            .offset(y: 110)
            .disabled(search != nil)

            // Search, Films, Séries — out of reach once the page has gone below its hero.
            CollectionFilterBar(filter: $typeFilter, onSearch: openSearch)
                .disabled(search != nil || (canvasFocused && index > 0))
                .opacity(search != nil ? 0 : 1)

            OrbitPlatformIntro(title: model.folderTitle, logoUrl: model.titleLogoUrl, brand: brand)

            if let search {
                OrbitPlatformSearchLayer(model: search, platform: model.folderTitle,
                                         onOpen: { push(TitleRoute(preview: $0)) },
                                         onClose: closeSearch)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight, alignment: .topLeading)
        .background(OrbitHomeLayout.background)
        .ignoresSafeArea()
        .background { ViewerInputClockInstaller().frame(width: 0, height: 0) }
        .onAppear {
            tabBarVisibility.pushImmersive()
            model.buildsStripState = true
            model.start()
            extras.load(title: model.folderTitle)
            trailer.restSource = .custom(motion)
            refreshAfterMove()
        }
        .onDisappear {
            tabBarVisibility.popImmersive()
            trailer.reset(abortStages: true)
            // Keeps the folder's state (a pushed title only covers the page; `initialize` on the
            // way back finds the same rows).
            model.stop()
        }
        .onChange(of: model.folderTitle) { _, title in extras.load(title: title) }
        .onChange(of: canvasFocused) { _, _ in refreshAfterMove() }
        .onChange(of: sections.map(\.id)) { _, _ in
            if current >= sections.count { current = max(0, sections.count - 1) }
            refreshAfterMove()
        }
        .onChange(of: typeFilter) { _, _ in
            current = 0
            heroIndex = 0
            leads = [:]
            refreshAfterMove()
        }
        // A series-only folder does not open on an empty Films page.
        .onChange(of: model.stripRows.map(\.id), initial: true) { _, _ in
            let all = model.stripRows
            if typeFilter == "movie", !all.isEmpty, CollectionTypeFilter.rows(all, filter: "movie").isEmpty,
               !CollectionTypeFilter.rows(all, filter: "series").isEmpty {
                typeFilter = "series"
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: Section, isCurrent: Bool, heroItem: MetaPreview?) -> some View {
        let focusedHere = isCurrent && canvasFocused
        switch section {
        case .hero:
            OrbitHomeHeroView(item: heroItem, focused: focusedHere,
                              trailerURL: trailerURL(for: "hero", id: heroItem.map { "\($0.type):\($0.id)" }),
                              onTrailerFailure: { trailer.playbackFailed($0) },
                              onTrailerEnded: { trailer.playbackFinished() })
                .offset(x: OrbitHomeLayout.margin)
        case .row(let row):
            let lead = min(leads[row.id] ?? 0, max(0, row.cards.count - 1))
            OrbitHomeRowView(row: row, lead: lead, isCurrent: isCurrent, focused: focusedHere,
                             trailerURL: row.cards.indices.contains(lead) ? trailerURL(for: row.id, id: row.cards[lead].id) : nil,
                             onTrailerFailure: { trailer.playbackFailed($0) },
                             onTrailerEnded: { trailer.playbackFinished() })
        }
    }

    private func trailerURL(for section: String, id: String?) -> String? {
        guard let id, trailerKey == "\(section)|\(id)" else { return nil }
        return trailer.playingURL
    }

    // MARK: Input

    private func move(_ direction: MoveCommandDirection) {
        let sections = sections
        guard !sections.isEmpty else { return }
        let index = min(current, sections.count - 1)
        switch direction {
        case .down:
            guard index + 1 < sections.count else { return }
            withAnimation(reduceMotion ? nil : OrbitHomeLayout.vertical) { current = index + 1 }
        case .up:
            guard index > 0 else { return }   // the bar takes it at the top
            withAnimation(reduceMotion ? nil : OrbitHomeLayout.vertical) { current = index - 1 }
        case .left, .right:
            let delta = direction == .right ? 1 : -1
            switch sections[index] {
            case .hero:
                let count = heroItems.count
                guard count > 1 else { return }
                withAnimation(OrbitHomeLayout.horizontal) { heroIndex = (heroIndex + delta + count) % count }
            case .row(let row):
                let lead = min(leads[row.id] ?? 0, row.cards.count - 1) + delta
                guard row.cards.indices.contains(lead) else { return }
                withAnimation(OrbitHomeLayout.horizontal) { leads[row.id] = lead }
            }
        @unknown default:
            return
        }
        refreshAfterMove()
    }

    private func select() {
        let sections = sections
        guard !sections.isEmpty else { return }
        switch sections[min(current, sections.count - 1)] {
        case .hero:
            guard !heroItems.isEmpty else { return }
            push(TitleRoute(preview: heroItems[heroIndex % heroItems.count]))
        case .row(let row):
            let lead = min(leads[row.id] ?? 0, row.cards.count - 1)
            guard row.cards.indices.contains(lead) else { return }
            push(TitleRoute(preview: row.cards[lead].preview))
        }
    }

    /// Menu: back to the top from below it; at the top, the system's own (the page closes).
    private func exitAction(index: Int) -> (() -> Void)? {
        guard index > 0 else { return nil }
        return { goTop() }
    }

    private func goTop() {
        withAnimation(reduceMotion ? nil : OrbitHomeLayout.vertical) { current = 0 }
        refreshAfterMove()
    }

    private func openSearch() {
        trailer.reset()
        trailerKey = nil
        withAnimation(.easeInOut(duration: 0.25)) { search = OrbitPlatformSearchModel(tabs: model.tabs) }
    }

    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.25)) { search = nil }
        refreshAfterMove()
    }

    /// After any move: the look-ahead (TMDB meta, frame art) and the trailer.
    private func refreshAfterMove() {
        let sections = sections
        let index = min(current, max(0, sections.count - 1))
        motion.stamp()

        var metaItems: [MetaPreview] = []
        let heroItems = self.heroItems
        if !heroItems.isEmpty {
            metaItems.append(contentsOf: (0..<min(3, heroItems.count)).map { heroItems[(heroIndex + $0) % heroItems.count] })
        }
        for i in max(0, index - 1)...max(0, min(sections.count - 1, index + 1)) where sections.indices.contains(i) {
            guard case .row(let row) = sections[i] else { continue }
            let lead = min(leads[row.id] ?? 0, max(0, row.cards.count - 1))
            let around = row.cards.indices.filter { $0 >= lead - 1 && $0 <= lead + 3 }
            metaItems.append(contentsOf: around.map { row.cards[$0].preview })
            let request = ArtworkDecodeRequest(size: .points(width: OrbitHomeLayout.frameWidth, height: OrbitHomeLayout.cardHeight),
                                               fill: true, scale: UIScreen.main.scale)
            ArtworkStore.prefetch(around.compactMap { j in
                row.cards[j].landscape.flatMap(URL.init(string:)).map { ArtworkPrefetchItem(url: $0, decode: request) }
            })
        }
        OrbitMetaStore.shared.request(metaItems)

        trailer.reset()
        trailerKey = nil
        guard trailersOn, canvasFocused, search == nil, UIAccessibility.isVideoAutoplayEnabled,
              sections.indices.contains(index) else { return }
        trailer.prefersReducedMotion = reduceMotion
        trailer.restSource = .custom(motion)
        switch sections[index] {
        case .hero:
            guard !heroItems.isEmpty else { return }
            let item = heroItems[heroIndex % heroItems.count]
            trailerKey = "hero|\(item.type):\(item.id)"
            trailer.focusChanged(true, item: item)
        case .row(let row):
            let lead = min(leads[row.id] ?? 0, max(0, row.cards.count - 1))
            guard row.cards.indices.contains(lead) else { return }
            let card = row.cards[lead]
            trailerKey = "\(row.id)|\(card.id)"
            trailer.focusChanged(true, item: card.preview)
        }
    }
}

/// No system focus effect: the page draws its own.
private struct OrbitPlatformCanvasStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Brand

/// Each platform's colour (its brand's, darkened for a background), from the folder's title. A
/// folder not listed (a studio…) takes a neutral slate.
enum OrbitPlatformBrand {
    static func color(title raw: String) -> Color {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        if t.contains("netflix") { return Color(red: 0.78, green: 0.04, blue: 0.08) }
        if t.contains("disney") { return Color(red: 0.06, green: 0.22, blue: 0.62) }
        if t.contains("prime") || t.contains("amazon") { return Color(red: 0.0, green: 0.48, blue: 0.78) }
        if t.contains("hbo") || t == "max" || t.hasPrefix("max") { return Color(red: 0.16, green: 0.12, blue: 0.75) }
        if t.contains("paramount") { return Color(red: 0.0, green: 0.33, blue: 0.85) }
        if t.contains("appletv") || t.contains("apple") { return Color(white: 0.55) }
        if t.contains("canal") { return Color(white: 0.45) }
        if t.contains("crunchyroll") { return Color(red: 0.96, green: 0.46, blue: 0.08) }
        if t.contains("universal") { return Color(red: 0.12, green: 0.30, blue: 0.70) }
        if t.contains("pixar") { return Color(red: 0.10, green: 0.45, blue: 0.80) }
        if t.contains("marvel") { return Color(red: 0.75, green: 0.08, blue: 0.10) }
        if t.contains("dreamworks") { return Color(red: 0.10, green: 0.35, blue: 0.75) }
        return Color(red: 0.30, green: 0.34, blue: 0.42)
    }
}

/// The page's background: the platform's colour glowing from the top-right corner (where its logo
/// sits), fading into Orbit's black.
private struct OrbitPlatformBackground: View {
    let brand: Color

    var body: some View {
        ZStack {
            OrbitHomeLayout.background
            RadialGradient(colors: [brand.opacity(0.55), brand.opacity(0.18), .clear],
                           center: UnitPoint(x: 0.9, y: 0.05), startRadius: 0, endRadius: 1500)
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: brand)
    }
}

// MARK: - Intro

/// The platform's logo, large on a screen tinted with its colour, then gliding to the top-right
/// corner while the tint fades (an app opening on Apple TV). Once per visit; any press skips it;
/// Reduce Motion goes straight to the corner.
private struct OrbitPlatformIntro: View {
    let title: String
    let logoUrl: String?
    let brand: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .hidden
    @State private var glide: DispatchWorkItem?

    private enum Phase { case hidden, splash, settled }

    static let logoSize = CGSize(width: 520, height: 200)
    static let splashScale: CGFloat = 1.4
    static let cornerScale: CGFloat = 0.36
    /// The corner: level with the bar's centre line, at the right margin.
    static let cornerCentreY: CGFloat = 59
    static let cornerTrailing: CGFloat = 72

    var body: some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        let size = Self.logoSize
        let scale: CGFloat = switch phase {
        case .hidden: Self.splashScale * 0.85
        case .splash: Self.splashScale
        case .settled: Self.cornerScale
        }
        let centre: CGPoint = phase == .settled
            ? CGPoint(x: W - Self.cornerTrailing - size.width * Self.cornerScale / 2, y: Self.cornerCentreY)
            : CGPoint(x: W / 2, y: H / 2)
        ZStack(alignment: .topLeading) {
            // Black tinted with the platform's colour.
            ZStack {
                Color.black
                RadialGradient(colors: [brand.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 900)
            }
            .frame(width: W, height: H)
            .opacity(phase == .settled ? 0 : 1)

            logo
                .frame(width: size.width, height: size.height, alignment: phase == .settled ? .trailing : .center)
                .scaleEffect(scale, anchor: .center)
                .opacity(phase == .hidden ? 0 : 1)
                .offset(x: centre.x - size.width / 2, y: centre.y - size.height / 2)
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .allowsHitTesting(false)
        .onAppear(perform: play)
        .onReceive(NotificationCenter.default.publisher(for: ViewerInputClock.didRecord)) { _ in
            // Steven: a press skips the intro (the page is used often).
            guard phase != .settled else { return }
            glide?.cancel()
            withAnimation(.easeOut(duration: 0.3)) { phase = .settled }
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let logoUrl, !logoUrl.isEmpty {
            CachedAsyncImage(string: logoUrl, contentMode: .fit,
                             decodeSize: .points(width: Self.logoSize.width * Self.splashScale,
                                                 height: Self.logoSize.height * Self.splashScale),
                             loading: { Color.clear }, failure: { name })
        } else {
            name
        }
    }

    private var name: some View {
        Text(title)
            .font(.system(size: 90, weight: .heavy))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }

    private func play() {
        guard phase == .hidden else { return }
        if reduceMotion {
            phase = .settled
            return
        }
        withAnimation(.easeOut(duration: 0.35)) { phase = .splash }
        let work = DispatchWorkItem {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.88)) { phase = .settled }
        }
        glide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95, execute: work)
    }
}

// MARK: - Franchises and genres (TMDB)

/// The platform's own extra rows: Disney+'s franchises (Marvel, Star Wars, Pixar), then six genres
/// — TMDB's discover by watch provider in the viewer's region, the most popular first, so only
/// what is on the platform. Fetched once per page; a platform TMDB does not know has none.
@MainActor
final class OrbitPlatformExtrasModel: ObservableObject {
    @Published private(set) var movieRows: [OrbitRow] = []
    @Published private(set) var seriesRows: [OrbitRow] = []
    private var loadedFor: Int?

    nonisolated private static let movieGenres: [(Int, String)] = [
        (28, "Action"), (35, "Comédie"), (53, "Thriller"), (27, "Horreur"), (878, "Science-Fiction"), (16, "Animation"),
    ]
    nonisolated private static let seriesGenres: [(Int, String)] = [
        (18, "Drame"), (35, "Comédie"), (80, "Crime"), (10765, "Science-Fiction & Fantastique"),
        (16, "Animation"), (99, "Documentaire"),
    ]
    /// Disney+: (company id, row title, movies, series).
    nonisolated private static let disneyFranchises: [(Int, String)] = [(420, "Marvel"), (1, "Star Wars"), (3, "Pixar")]

    func load(title: String) {
        guard let provider = OrbitPlatformTrendingModel.providerId(forTitle: title), provider != loadedFor else { return }
        loadedFor = provider
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { return }
        let language = TmdbSettingsRepository.shared.snapshot().language
        let disney = provider == 337
        Task { [weak self] in
            async let movies = Self.rows(media: "movie", provider: provider, disney: disney, apiKey: key, language: language)
            async let series = Self.rows(media: "tv", provider: provider, disney: disney, apiKey: key, language: language)
            let (m, s) = await (movies, series)
            guard let self, self.loadedFor == provider else { return }
            self.movieRows = m.map { OrbitRow(id: $0.id, title: $0.title, cards: $0.items.map(OrbitCard.catalog)) }
            self.seriesRows = s.map { OrbitRow(id: $0.id, title: $0.title, cards: $0.items.map(OrbitCard.catalog)) }
        }
    }

    nonisolated private static func rows(media: String, provider: Int, disney: Bool,
                                         apiKey: String, language: String) async -> [(id: String, title: String, items: [MetaPreview])] {
        let tv = media == "tv"
        var specs: [(id: String, title: String, query: String)] = []
        if disney {
            for (company, name) in disneyFranchises where !(tv && company == 3) {
                specs.append(("franchise-\(company)-\(media)", name, "&with_companies=\(company)"))
            }
        }
        for (genre, name) in tv ? seriesGenres : movieGenres {
            specs.append(("genre-\(genre)-\(media)", name, "&with_genres=\(genre)"))
        }
        let lang = language.isEmpty ? "fr-FR" : language
        let region = region(language: lang)
        let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    let address = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(lang)"
                        + "&watch_region=\(region)&with_watch_providers=\(provider)"
                        + "&with_watch_monetization_types=flatrate&sort_by=popularity.desc&page=1" + spec.query
                    return (index, await fetch(address, tv: tv))
                }
            }
            var out: [Int: [MetaPreview]] = [:]
            for await (index, items) in group { out[index] = items }
            return out
        }
        return specs.enumerated().compactMap { index, spec in
            let items = lists[index] ?? []
            guard items.count >= 5 else { return nil }
            return (spec.id, spec.title, items)
        }
    }

    nonisolated private static func region(language: String) -> String {
        let parts = language.split(whereSeparator: { $0 == "-" || $0 == "_" })
        if parts.count > 1 { return String(parts[1]).uppercased() }
        if let region = Locale.current.region?.identifier, region.count == 2 { return region }
        return "FR"
    }

    nonisolated private struct Response: Decodable {
        nonisolated struct Result: Decodable {
            let id: Int
            let title: String?
            let name: String?
            let overview: String?
            let poster_path: String?
            let backdrop_path: String?
            let release_date: String?
            let first_air_date: String?
            let vote_average: Double?
        }
        let results: [Result]?
    }

    nonisolated private static func fetch(_ address: String, tv: Bool) async -> [MetaPreview] {
        guard let url = URL(string: address),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (decoded.results ?? []).compactMap { r -> MetaPreview? in
            guard let name = r.title ?? r.name, !name.isEmpty, let poster = r.poster_path else { return nil }
            let date = r.release_date ?? r.first_air_date
            return MetaPreview(id: "tmdb:\(r.id)", type: tv ? "series" : "movie", name: name,
                               poster: "https://image.tmdb.org/t/p/w500\(poster)",
                               banner: r.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                               logo: nil, posterShape: .poster,
                               description: r.overview, releaseInfo: date.map { String($0.prefix(4)) },
                               rawReleaseDate: date, popularity: nil, voteCount: nil,
                               imdbRating: r.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                               genres: [], rawPosterUrl: nil, landscapePoster: nil,
                               rawLandscapePosterUrl: nil, customPosterApplied: false)
        }
    }
}
