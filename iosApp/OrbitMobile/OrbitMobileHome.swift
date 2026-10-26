import SharedCore
import SwiftUI

// Orbit mobile Home: a vertical scroll, a hero carousel swiped by the finger, then the same rows as
// the Apple TV's Home (same data, same order, same tiles) scrolled sideways. Tiles are the TV's own
// views drawn at their TV size and scaled down (`OrbitMobileScaled`), so a design change on the TV
// shows here by itself.

/// Phone / iPad size of the TV's tiles (they are drawn for a 1920-point-wide screen).
enum OrbitMobileMetrics {
    static func tileFactor(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat { sizeClass == .regular ? 0.68 : 0.46 }
    static func margin(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat { sizeClass == .regular ? 28 : 16 }
}

/// A TV-sized view drawn at `factor` (its layout size scaled too, so rows and grids line up).
struct OrbitMobileScaled<Content: View>: View {
    let size: CGSize
    let factor: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(factor, anchor: .topLeading)
            .frame(width: size.width * factor, height: size.height * factor, alignment: .topLeading)
            .contentShape(Rectangle())
    }
}

struct OrbitMobileHome: View {
    enum Kind { case all, movies, series }

    @ObservedObject var model: HomeViewModel
    @ObservedObject var extras: OrbitHomeExtrasModel
    let kind: Kind

    @ObservedObject private var heroModel = StageTrendingHeroModel.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path = NavigationPath()
    @State private var resume: ResumeTarget?
    @State private var postPlayPick: MetaPreview?
    @State private var cache = OrbitRowsCache()

    private var heroItems: [MetaPreview] {
        switch kind {
        case .movies: return heroModel.items(series: false)
        case .series: return heroModel.items(series: true)
        case .all: return OrbitHomeRowsBuilder.interleave(heroModel.items(series: false), heroModel.items(series: true))
        }
    }

    private var rows: [OrbitRow] {
        let key = "\(kind)|" + OrbitHomeRowsBuilder.signature(model: model, extras: extras)
        if cache.key == key { return cache.rows }
        let built: [OrbitRow]
        switch kind {
        case .movies: built = OrbitHomeRowsBuilder.rows(series: false, model: model, extras: extras)
        case .series: built = OrbitHomeRowsBuilder.rows(series: true, model: model, extras: extras)
        case .all: built = OrbitHomeRowsBuilder.mixedRows(model: model, extras: extras)
        }
        cache.key = key
        cache.rows = built
        return built
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if !heroItems.isEmpty {
                        OrbitMobileHero(items: Array(heroItems.prefix(10))) { path.append(TitleRoute(preview: $0)) }
                    }
                    ForEach(rows) { row in
                        OrbitMobileRow(row: row, open: open)
                    }
                }
                .padding(.bottom, 30)
            }
            .ignoresSafeArea(edges: .top)
            .background(OrbitHomeLayout.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TitleRoute.self) { route in
                OrbitMobileDetail(preview: route.preview)
            }
            // Continue Watching: straight to the source picker, as on the TV (HomeView.resume).
            .fullScreenCover(item: $resume, onDismiss: {
                guard let pick = postPlayPick else { return }
                postPlayPick = nil
                path.append(TitleRoute(preview: pick))
            }) { target in
                StreamPickerView(type: target.entry.parentMetaType,
                                 videoId: target.entry.videoId,
                                 title: target.entry.title,
                                 parentMetaId: target.entry.parentMetaId,
                                 season: target.entry.seasonNumber?.value,
                                 episode: target.entry.episodeNumber?.value,
                                 poster: target.entry.poster,
                                 episodeStill: { let s: String? = target.entry.episodeThumbnail; return (s ?? "").isEmpty ? nil : s }(),
                                 synopsis: { let d: String? = target.entry.pauseDescription; return (d ?? "").isEmpty ? nil : d }(),
                                 forceManual: target.forceManual,
                                 startFromBeginning: target.startFromBeginning,
                                 onOpenTitle: { postPlayPick = $0 })
            }
        }
        .onAppear {
            heroModel.loadIfNeeded()
            extras.load()
            loadBecause()
            OrbitMetaStore.shared.request(Array(heroItems.prefix(3)))
        }
        .onChange(of: model.continueWatching.count) { _, _ in loadBecause() }
    }

    /// "Parce que vous avez regardé …" for the page's kind (both on Accueil).
    private func loadBecause() {
        let kinds: [Bool] = kind == .all ? [false, true] : [kind == .series]
        for series in kinds {
            extras.loadBecause(seed: OrbitHomeRowsBuilder.becauseSeed(series: series, model: model), series: series)
        }
    }

    private func open(_ card: OrbitCard) {
        if let entry = card.entry {
            resume = ResumeTarget(entry: entry)
        } else {
            path.append(TitleRoute(preview: card.preview))
        }
    }
}

// MARK: - Hero

/// The hero: one page per title, swiped (TabView page style), moving on by itself every 8 s.
private struct OrbitMobileHero: View {
    let items: [MetaPreview]
    let open: (MetaPreview) -> Void

    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var page = 0

    var body: some View {
        let regular = sizeClass == .regular
        GeometryReader { geo in
            let size = geo.size
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button { open(item) } label: { heroPage(item, size: size, regular: regular) }
                        .buttonStyle(OrbitPlainStyle())
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        // A tall poster on a phone (as Netflix's), the 16:9 art on an iPad.
        .aspectRatio(regular ? 16 / 9 : 2 / 3, contentMode: .fit)
        .onChange(of: page) { _, index in
            if items.indices.contains(index + 1) { metaStore.request([items[index + 1]]) }
        }
        .task(id: page) {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, !items.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.5)) { page = (page + 1) % items.count }
        }
    }

    private func heroPage(_ item: MetaPreview, size: CGSize, regular: Bool) -> some View {
        let meta = metaStore.meta(for: item)
        let info = OrbitInfo.make(item, meta: meta)
        let art = regular ? (meta?.backdrop ?? heroBackdropURL(for: item)) : (meta?.localPoster ?? item.poster)
        return ZStack(alignment: .bottomLeading) {
            Color(white: 0.08)
            OrbitImage(url: art, fallback: regular ? item.poster : heroBackdropURL(for: item), size: size)
            LinearGradient(stops: [.init(color: .clear, location: 0.45),
                                   .init(color: OrbitHomeLayout.background.opacity(0.85), location: 0.82),
                                   .init(color: OrbitHomeLayout.background, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                OrbitTitleMark(name: item.name, logo: info.logo,
                               maxSize: CGSize(width: size.width * 0.62, height: size.height * 0.16),
                               textSize: regular ? 40 : 30, fallbackLogo: info.logoFallback)
                OrbitMetaLine(info: info, size: regular ? 17 : 14)
            }
            .padding(.horizontal, OrbitMobileMetrics.margin(sizeClass))
            .padding(.bottom, 44)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

// MARK: - A row

private struct OrbitMobileRow: View {
    let row: OrbitRow
    let open: (OrbitCard) -> Void

    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let factor = OrbitMobileMetrics.tileFactor(sizeClass)
        let margin = OrbitMobileMetrics.margin(sizeClass)
        VStack(alignment: .leading, spacing: 10) {
            OrbitRowHeading(title: row.title, isCurrent: true, size: sizeClass == .regular ? 22 : 18)
                .padding(.leading, margin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: OrbitTileLayout.gap(row.style) * factor) {
                    ForEach(Array(row.cards.enumerated()), id: \.element.id) { index, card in
                        Button { open(card) } label: { tile(card, rank: index + 1, factor: factor) }
                            .buttonStyle(OrbitPlainStyle())
                            .onAppear { metaStore.request([card.preview]) }
                    }
                }
                .padding(.horizontal, margin)
            }
        }
    }

    @ViewBuilder
    private func tile(_ card: OrbitCard, rank: Int, factor: CGFloat) -> some View {
        let meta = metaStore.meta(for: card.preview)
        let T = OrbitTileLayout.self
        switch row.style {
        case .landscape:
            OrbitMobileScaled(size: T.landscape, factor: factor) {
                OrbitLandscapeTile(card: card, meta: meta, focused: false)
            }
        case .classic:
            // The TV's classic row opens its focused title in a 16:9 frame; with no focus, posters.
            OrbitMobileScaled(size: T.size(.classic), factor: factor) { OrbitPosterCard(card: card) }
        case .cards:
            OrbitMobileScaled(size: T.card, factor: factor) {
                OrbitBigCard(card: card, meta: meta, focused: false, trailerURL: nil,
                             onTrailerFailure: { _ in }, onTrailerEnded: {})
            }
        case .ranked:
            let width = T.rankWidth + T.rankedPoster.width + (rank >= 10 ? T.tenExtra : 0)
            OrbitMobileScaled(size: CGSize(width: width, height: T.rankedPoster.height), factor: factor) {
                OrbitRankedTile(card: card, meta: meta, rank: rank, focused: false)
            }
        case .posters:
            OrbitMobileScaled(size: T.poster, factor: factor) { OrbitSmallPoster(card: card, meta: meta, focused: false) }
        case .sagas:
            OrbitMobileScaled(size: T.sagaPoster, factor: factor) {
                OrbitSmallPoster(card: card, meta: meta, focused: false, size: T.sagaPoster)
            }
        }
    }
}

// MARK: - Rows builder

/// TEMPORARY COPY of `OrbitHomeView.buildRows()` / `rowsSignature()` / `card(_:_:)` /
/// `becauseSeed(series:)` (OrbitHomeView.swift, private there). To be extracted on the Mac: move
/// this enum into a shared file (e.g. Screens/OrbitHome/OrbitHomeRowsBuilder.swift), make
/// `OrbitHomeView.buildRows()` call `OrbitHomeRowsBuilder.rows(series:model:extras:)`, and delete
/// the private copies there — then a row reordered on the TV reorders here too.
@MainActor
enum OrbitHomeRowsBuilder {
    static func rows(series: Bool, model: HomeViewModel, extras: OrbitHomeExtrasModel) -> [OrbitRow] {
        var out: [OrbitRow] = []
        var seen = Set<String>()
        let entries = model.continueWatching.filter { series ? $0.parentMetaType != "movie" : $0.parentMetaType == "movie" }
        if !entries.isEmpty {
            out.append(OrbitRow(id: "continue-watching", title: String(localized: "Reprendre"),
                                cards: unique(entries.map(OrbitCard.continueWatching)), style: .landscape))
            seen.insert("continue-watching")
        }
        let because = series ? extras.becauseSeries : extras.becauseMovie
        let extraRows = ((series ? extras.seriesRows : extras.movieRows) + [because].compactMap { $0 }).map { extra in
            OrbitRow(id: extra.id, title: extra.title, cards: unique(extra.items.map { card(extra.id, $0) }), style: extra.style)
        }
        var top = extraRows.filter { $0.style == .ranked }
        let order = ["orbit-because", "orbit-new", "orbit-soon", "orbit-sagas", "orbit-best"]
        var platforms = extraRows.filter { $0.style != .ranked }
            .sorted { a, b in
                (order.firstIndex { a.id.hasPrefix($0) } ?? 9) < (order.firstIndex { b.id.hasPrefix($0) } ?? 9)
            }
        let cycle: [OrbitRowStyle] = [.cards, .classic, .posters]
        var catalogs = 0
        var styled = 0
        for row in model.rows {
            guard case .catalog(let section) = row else { continue }
            let movie = section.target.contentType == "movie"
            guard series ? !movie : movie, !section.items.isEmpty, seen.insert(section.key).inserted else { continue }
            let heading = section.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let isTop = heading.contains("top 10") || heading.contains("top10")
            if isTop, extraRows.contains(where: { $0.style == .ranked }) { continue }
            var style: OrbitRowStyle = .classic
            if !isTop {
                style = styled == 0 ? .classic : cycle[(styled - 1) % cycle.count]
                styled += 1
            }
            out.append(OrbitRow(id: section.key, title: section.title, cards: unique(section.items.map(OrbitCard.catalog)),
                                sectionKey: section.key, style: style))
            catalogs += 1
            if catalogs == 1, !top.isEmpty { out.append(top.removeFirst()) }
            if catalogs >= 2, !platforms.isEmpty { out.append(platforms.removeFirst()) }
        }
        return out + top + platforms
    }

    /// Accueil (mobile only): Reprendre for everything, then the films' and the series' rows in turn.
    static func mixedRows(model: HomeViewModel, extras: OrbitHomeExtrasModel) -> [OrbitRow] {
        let movies = rows(series: false, model: model, extras: extras).filter { $0.id != "continue-watching" }
        let shows = rows(series: true, model: model, extras: extras).filter { $0.id != "continue-watching" }
        var out: [OrbitRow] = []
        if !model.continueWatching.isEmpty {
            out.append(OrbitRow(id: "continue-watching", title: String(localized: "Reprendre"),
                                cards: unique(model.continueWatching.map(OrbitCard.continueWatching)), style: .landscape))
        }
        return out + interleave(movies, shows)
    }

    static func interleave<T>(_ a: [T], _ b: [T]) -> [T] {
        var out: [T] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    /// What the rows are made of (rebuilt only when it changes), as `OrbitHomeView.rowsSignature()`.
    static func signature(model: HomeViewModel, extras: OrbitHomeExtrasModel) -> String {
        var k = ""
        for e in model.continueWatching { k += "\(e.videoId):\(e.lastUpdatedEpochMs)," }
        k += "|"
        for extra in extras.movieRows + extras.seriesRows + [extras.becauseMovie, extras.becauseSeries].compactMap({ $0 }) {
            k += "\(extra.id)#\(extra.items.count)#\(extra.items.first?.id ?? ""),"
        }
        k += "|"
        for row in model.rows {
            guard case .catalog(let section) = row else { continue }
            let items = section.items
            k += "\(section.key)#\(items.count)#\(items.first?.id ?? "")#\(items.last?.id ?? ""),"
        }
        return k
    }

    static func becauseSeed(series: Bool, model: HomeViewModel) -> (id: String, name: String)? {
        let entry = model.continueWatching
            .filter { series ? $0.parentMetaType != "movie" : $0.parentMetaType == "movie" }
            .max { $0.lastUpdatedEpochMs < $1.lastUpdatedEpochMs }
        let watched = (WatchedRepository.shared.uiState.value_ as? WatchedUiState)?.items
            .filter { series ? $0.type != "movie" : $0.type == "movie" }
            .max { $0.markedAtEpochMs < $1.markedAtEpochMs }
        if let watched, watched.markedAtEpochMs > (entry?.lastUpdatedEpochMs ?? 0) { return (watched.id, watched.name) }
        if let entry { return (entry.parentMetaId, entry.title) }
        return nil
    }

    private static func card(_ rowId: String, _ item: MetaPreview) -> OrbitCard {
        var card = OrbitCard.catalog(item)
        if rowId.hasPrefix("orbit-sagas") {
            card = OrbitCard(id: "saga:\(item.id)", preview: item, poster: item.poster, landscape: card.landscape)
        }
        if rowId.hasPrefix("orbit-soon"), let raw = item.rawReleaseDate, raw.count >= 10,
           let date = isoDay.date(from: String(raw.prefix(10))) {
            card.badge = String(localized: "Le \(shortDay.string(from: date))")
        }
        return card
    }

    private static func unique(_ cards: [OrbitCard]) -> [OrbitCard] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.id).inserted }
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()
}
