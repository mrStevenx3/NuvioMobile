import Combine
import SharedCore
import SwiftUI

// Orbit Plateformes (Steven, 2026-10-23, on trial): under the platforms, "Films populaires sur
// <platform>" and "Séries populaires sur <platform>" — TMDB's discover by watch provider in the
// viewer's region, by popularity (it is what is popular there, not only what is new: hence
// "populaires"). Each row scrolls sideways through its 20 titles. The rows follow the last focused
// platform, so the viewer sees what is inside before opening it. A platform TMDB does not know
// shows no rows.

@MainActor
final class OrbitPlatformTrendingModel: ObservableObject {
    static let shared = OrbitPlatformTrendingModel()

    @Published private(set) var title: String?
    @Published private(set) var movies: [MetaPreview] = []
    @Published private(set) var series: [MetaPreview] = []
    /// Steven (2026-10-25): "Top 10 sur <platform>" — its ten most popular titles, films and series.
    @Published private(set) var top: [MetaPreview] = []
    /// The art faded in behind the page: the focused title's, else the platform's number one.
    @Published var spotlight: String?

    private typealias Found = (movies: [MetaPreview], series: [MetaPreview], top: [MetaPreview])
    private var cache: [Int: Found] = [:]
    private var pending: Task<Void, Never>?
    private var current: Int?

    /// TMDB's watch-provider id for a platform folder, from its title.
    static func providerId(forTitle raw: String) -> Int? {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        if t.contains("netflix") { return 8 }
        if t.contains("disney") { return 337 }
        if t.contains("prime") || t.contains("amazon") { return 119 }
        if t.contains("hbo") || t == "max" || t.hasPrefix("max") { return 1899 }
        if t.contains("paramount") { return 531 }
        if t.contains("appletv") || t.contains("apple") { return 350 }
        if t.contains("canal") { return 381 }
        if t.contains("universal") { return 2420 }
        return nil
    }

    /// The focused platform changed: its row, after a short rest (a fast pass over the grid
    /// fetches nothing).
    func focus(title folderTitle: String) {
        guard let provider = Self.providerId(forTitle: folderTitle) else {
            pending?.cancel()
            current = nil
            withAnimation(.easeInOut(duration: 0.25)) { title = nil; movies = []; series = []; top = []; spotlight = nil }
            return
        }
        guard provider != current else { return }
        current = provider
        pending?.cancel()
        if let cached = cache[provider] {
            apply(cached, title: folderTitle)
            return
        }
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        let language = TmdbSettingsRepository.shared.snapshot().language
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let found = await Self.fetch(provider: provider, apiKey: key, language: language)
            guard !Task.isCancelled, let self, self.current == provider else { return }
            self.cache[provider] = found
            self.apply(found, title: folderTitle)
        }
    }

    private func apply(_ found: Found, title folderTitle: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            title = found.movies.isEmpty && found.series.isEmpty && found.top.isEmpty ? nil : folderTitle
            movies = found.movies
            series = found.series
            top = found.top
        }
        spotlight = Self.featured(found)
        // Logos for the landscape tiles, the French posters for the Top 10.
        OrbitMetaStore.shared.request(found.top + Array(found.movies.prefix(12)))
    }

    /// The platform's number one with art (the page's backdrop while no title is focused).
    private static func featured(_ found: Found) -> String? {
        (found.top + found.movies + found.series).lazy.compactMap(\.banner).first
    }

    /// The platform's own art back (the focus left the titles).
    func resetSpotlight() {
        guard let provider = current, let found = cache[provider] else { return }
        spotlight = Self.featured(found)
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
            let popularity: Double?
        }
        let results: [Result]?
    }

    nonisolated private static func region(language: String) -> String {
        let parts = language.split(whereSeparator: { $0 == "-" || $0 == "_" })
        if parts.count > 1 { return String(parts[1]).uppercased() }
        if let region = Locale.current.region?.identifier, region.count == 2 { return region }
        return "FR"
    }

    nonisolated private static func fetch(provider: Int, apiKey: String,
                                          language: String) async -> (movies: [MetaPreview], series: [MetaPreview], top: [MetaPreview]) {
        let lang = language.isEmpty ? "fr-FR" : language
        let region = region(language: lang)
        async let movies = page(media: "movie", provider: provider, region: region, apiKey: apiKey, language: lang)
        async let series = page(media: "tv", provider: provider, region: region, apiKey: apiKey, language: lang)
        async let topMovies = page(media: "movie", provider: provider, region: region, apiKey: apiKey, language: lang, popular: true)
        async let topSeries = page(media: "tv", provider: provider, region: region, apiKey: apiKey, language: lang, popular: true)
        let (m, s, tm, ts) = await (movies, series, topMovies, topSeries)
        // Films and series together, the most popular first.
        let top = (tm + ts).sorted { ($0.popularity?.doubleValue ?? 0) > ($1.popularity?.doubleValue ?? 0) }
        return (m, s, Array(top.prefix(20)))
    }

    nonisolated private static func page(media: String, provider: Int, region: String, apiKey: String,
                                         language: String, popular: Bool = false) async -> [MetaPreview] {
        // Steven: the new titles, not the all-time popular ones. What came out on the platform in
        // the last four months (series: episodes aired in that window), the most popular first;
        // the plain popular list when the window has too few.
        let tv = media == "tv"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        let since = formatter.string(from: Date().addingTimeInterval(-120 * 24 * 3600))
        let window = tv ? "&air_date.gte=\(since)&air_date.lte=\(today)"
                        : "&primary_release_date.gte=\(since)&primary_release_date.lte=\(today)"
        let base = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(language)"
            + "&watch_region=\(region)&with_watch_providers=\(provider)"
            + "&with_watch_monetization_types=flatrate&sort_by=popularity.desc&page=1"
        // The Top 10: what is popular there now among what is out (no window).
        var found = await Self.results(popular ? base + (tv ? "" : "&primary_release_date.lte=\(today)") : base + window)
        if !popular, found.count < 8 {
            let popular = await Self.results(base)
            let seen = Set(found.map(\.id))
            found += popular.filter { !seen.contains($0.id) }
        }
        return found.compactMap { r -> MetaPreview? in
            guard let name = r.title ?? r.name, !name.isEmpty, let poster = r.poster_path else { return nil }
            let date = r.release_date ?? r.first_air_date
            return MetaPreview(id: "tmdb:\(r.id)", type: tv ? "series" : "movie", name: name,
                               poster: "https://image.tmdb.org/t/p/w780\(poster)",
                               banner: r.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                               logo: nil, posterShape: .poster,
                               description: r.overview, releaseInfo: date.map { String($0.prefix(4)) },
                               rawReleaseDate: date, popularity: r.popularity.map { KotlinDouble(double: $0) }, voteCount: nil,
                               imdbRating: r.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                               genres: [], rawPosterUrl: nil, landscapePoster: nil,
                               rawLandscapePosterUrl: nil, customPosterApplied: false)
        }
    }

    nonisolated private static func results(_ address: String) async -> [Response.Result] {
        guard let url = URL(string: address),
              let response = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: response.0) else { return [] }
        return decoded.results ?? []
    }
}

/// The rows under the platforms (Steven, 2026-10-25: as varied as Home): "Top 10 sur Netflix"
/// (Home's ranked posters), "Nouveaux films sur Netflix" in landscape tiles, "Nouveautés séries
/// sur Netflix" in posters. Each scrolls sideways; each title opens its page.
struct OrbitPlatformTrendingRow: View {
    @ObservedObject var model = OrbitPlatformTrendingModel.shared
    /// The row the focus is in (nil: out of the rows), for the page to bring it to its line.
    var onRowFocus: (String?) -> Void = { _ in }
    /// The focused platform's colour (the headings' bar).
    var accent: Color? = nil
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @FocusState private var focused: String?
    /// When the focus last left the rows (the platforms keep their own landing when coming back up).
    @MainActor static var lostAt: TimeInterval = 0
    /// Steven (device: back from a title opened in these rows, the focus went to the platform's
    /// tile): the title it was opened from, given the focus back on the return.
    @MainActor private static var lastFocused: String?
    @MainActor private static var restore: String?
    @MainActor private static var restoreUntil: TimeInterval = 0
    @MainActor static var restorePending: Bool {
        restore != nil && ProcessInfo.processInfo.systemUptime < restoreUntil
    }

    /// The page went away just after the focus left these rows: a title of theirs was opened.
    @MainActor static func notePushIfFromRows() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lostAt < 1.0, let lastFocused else { return }
        restore = lastFocused
        restoreUntil = now + 4
    }

    /// Steven: the page moves a row at a time — the focused row's heading sits here.
    static let rowLine: CGFloat = 150
    /// Steven (2026-10-25: "tout est trop grand" — the page is a preview of the platform): smaller.
    /// Steven: the Top 20, the new films and the new series all on one screen under the platforms.
    /// (Two rows — the Top 20, then the new films and series together — so the platforms above
    /// can be larger.)
    static let posterWidth: CGFloat = 156
    static let posterHeight: CGFloat = 234
    /// The 16:9 tiles, from Home's size.
    static let landscapeScale: CGFloat = 0.68
    static let spacing: CGFloat = 24

    private enum Kind { case ranked, landscape, posters }

    /// Films and series in turn, each title once.
    static func alternate(_ a: [MetaPreview], _ b: [MetaPreview]) -> [MetaPreview] {
        var out: [MetaPreview] = []
        var seen = Set<String>()
        for i in 0..<max(a.count, b.count) {
            for list in [a, b] where i < list.count {
                if seen.insert("\(list[i].type):\(list[i].id)").inserted { out.append(list[i]) }
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let title = model.title {
                if model.top.count >= 5 {
                    row(heading: String(format: String(localized: "Top 20 sur %@"), title),
                        items: model.top, key: "top-\(title)", kind: .ranked)
                }
                // Steven: one row of the new films and series, in turn (the platforms above grow).
                let fresh = Self.alternate(model.movies, model.series)
                if !fresh.isEmpty {
                    row(heading: String(format: String(localized: "Nouveaux films et séries sur %@"), title),
                        items: fresh, key: "fresh-\(title)", kind: .posters)
                }
            }
        }
        .onAppear { restoreFocus() }
        .onChange(of: focused) { old, id in
            guard let id else {
                Self.lostAt = ProcessInfo.processInfo.systemUptime
                model.resetSpotlight()
                return
            }
            Self.lastFocused = id
            if id == Self.restore { Self.restore = nil }
            let rowKey = String(id.prefix { $0 != "/" })
            if old.map({ String($0.prefix { $0 != "/" }) }) != rowKey { onRowFocus(rowKey) }
            let items = items(rowKey)
            // The page's art follows the focused title.
            if let item = items.first(where: { "\(rowKey)/\($0.id)" == id }) {
                model.spotlight = item.banner ?? metaStore.meta(for: item)?.backdrop ?? model.spotlight
            }
            // Steven: no return to a row's start — the focus lands where the system puts it.
        }
    }

    /// Back from a title: its poster, asked a few times (the system's own landing comes late).
    private func restoreFocus() {
        guard Self.restorePending, let target = Self.restore else { return }
        let appeared = ProcessInfo.processInfo.systemUptime
        for delay in [0.0, 0.15, 0.35, 0.6, 0.9, 1.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard Self.restore == target, !ViewerInputClock.shared.hasInput(since: appeared) else { return }
                if focused != target { focused = target }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if Self.restore == target { Self.restore = nil }
        }
    }

    private func items(_ rowKey: String) -> [MetaPreview] {
        guard let title = model.title else { return [] }
        switch rowKey {
        case "top-\(title)": return model.top
        case "fresh-\(title)": return Self.alternate(model.movies, model.series)
        default: return []
        }
    }

    private func row(heading: String, items: [MetaPreview], key: String, kind: Kind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Steven: Home's headings here too, the bar in the platform's colour.
            OrbitRowHeading(title: heading, isCurrent: true, accent: accent, size: 28)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: kind == .ranked ? 18 : Self.spacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let lit = focused == "\(key)/\(item.id)"
                        NavigationLink(value: TitleRoute(preview: item)) {
                            switch kind {
                            case .ranked:
                                OrbitRankedTile(card: OrbitCard(id: item.id, preview: item, poster: item.poster, landscape: item.banner),
                                                meta: metaStore.meta(for: item), rank: index + 1, focused: lit,
                                                // Steven: smaller here (it was cut at the top of the
                                                // screen once the page scrolled): the series' posters' height.
                                                showsBadge: false, scale: Self.posterHeight / OrbitTileLayout.rankedPoster.height)
                            case .landscape:
                                OrbitLandscapeTile(card: OrbitCard(id: item.id, preview: item, poster: item.poster, landscape: item.banner),
                                                   meta: metaStore.meta(for: item), focused: lit, showsBadge: false)
                                    .scaleEffect(Self.landscapeScale, anchor: .topLeading)
                                    .frame(width: OrbitTileLayout.landscape.width * Self.landscapeScale,
                                           height: OrbitTileLayout.landscape.height * Self.landscapeScale,
                                           alignment: .topLeading)
                            case .posters:
                                OrbitTrendingPoster(item: item, focused: lit)
                            }
                        }
                        .buttonStyle(OrbitPlatformTileStyle())
                        .focused($focused, equals: "\(key)/\(item.id)")
                    }
                }
                .padding(.vertical, 20)
                .padding(.trailing, OrbitHomeLayout.margin)
            }
            .scrollClipDisabled()
            .padding(.vertical, -20)
        }
        // The row's line on the page: its heading this far under the screen's top once scrolled to.
        .overlay(alignment: .top) {
            Color.clear.frame(width: 1, height: 1)
                .alignmentGuide(.top) { $0[.top] + Self.rowLine }
                .id("\(key)-line")
        }
        .id(key)
        .transition(.opacity)
        .focusSection()
    }
}

private struct OrbitTrendingPoster: View {
    let item: MetaPreview
    let focused: Bool

    var body: some View {
        let size = CGSize(width: OrbitPlatformTrendingRow.posterWidth, height: OrbitPlatformTrendingRow.posterHeight)
        ZStack {
            Color(white: 0.12)
            OrbitImage(url: item.poster, size: size)
        }
        .frame(width: size.width, height: size.height)
        .modifier(OrbitTileFocus(focused: focused, radius: 10))
        .accessibilityLabel(item.name)
    }
}
