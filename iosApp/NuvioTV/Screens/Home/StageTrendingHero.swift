import Combine
import SharedCore
import SwiftUI

// Steven's fork (Orbit Home): a hero at the very top of Home's Films and Séries pages, cycling
// through TMDB's trending titles of the DAY (`trending/movie/day`, `trending/tv/day`; Steven
// already has the week's as a catalog). It is the strip's first row: one focusable stop (Select
// opens the title, Left / Right go to the previous / next one, it moves on by itself every few
// seconds), and its title is reported to the stage like any focused card.
//
// Two styles (Home Screen ▸ "Hero plein écran"):
//  - card: the backdrop in a wide rounded card, text on it;
//  - full screen (wako): the stage itself shows the hero's backdrop sharp, full bleed, fading into
//    the blurred page below; the row draws only the text and a "Voir la fiche" pill.
// While the hero is the strip's current page (`StageHeroFocus.heroOnTop`) the stage's corner logo
// and info band hide; once the strip pages past it the hero fades out (it peeked above the rows).

/// Home Screen settings (Stage layout).
nonisolated enum StageTrendingHeroSetting {
    static let defaultsKey = "stage_trending_hero"
    static let defaultValue = true
    static let fullBleedKey = "stage_trending_hero_full_bleed"
    static let rowKey = "trending-hero"
}

/// The hero's titles, loaded once per session (again after three hours).
@MainActor
final class StageTrendingHeroModel: ObservableObject {
    static let shared = StageTrendingHeroModel()

    @Published private(set) var movies: [MetaPreview] = []
    @Published private(set) var series: [MetaPreview] = []
    private var loadedAt: Date?
    private var loading = false

    private init() {}

    func items(series wantsSeries: Bool) -> [MetaPreview] { wantsSeries ? series : movies }

    func loadIfNeeded() {
        if loading { return }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 3 * 3600, !movies.isEmpty || !series.isEmpty { return }
        loading = true
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        let language = TmdbSettingsRepository.shared.snapshot().language
        Task {
            async let m = Self.fetch(tv: false, apiKey: key, language: language)
            async let s = Self.fetch(tv: true, apiKey: key, language: language)
            let (films, shows) = await (m, s)
            self.loading = false
            if !films.isEmpty { self.movies = films }
            if !shows.isEmpty { self.series = shows }
            if !films.isEmpty || !shows.isEmpty { self.loadedAt = Date() }
            NSLog("[TrendingHero] loaded films=%d series=%d", films.count, shows.count)
        }
    }

    nonisolated private struct TrendingResponse: Decodable {
        nonisolated struct Result: Decodable { let id: Int }
        let results: [Result]?
    }

    nonisolated private struct Details: Decodable {
        nonisolated struct Genre: Decodable { let name: String? }
        nonisolated struct Logo: Decodable {
            let file_path: String?
            let iso_639_1: String?
        }
        nonisolated struct Images: Decodable { let logos: [Logo]? }
        nonisolated struct External: Decodable { let imdb_id: String? }
        let id: Int
        let imdb_id: String?
        let title: String?
        let name: String?
        let overview: String?
        let poster_path: String?
        let backdrop_path: String?
        let release_date: String?
        let first_air_date: String?
        let vote_average: Double?
        let genres: [Genre]?
        let images: Images?
        let external_ids: External?
    }

    nonisolated static let limit = 10

    nonisolated private static func fetch(tv: Bool, apiKey: String, language: String) async -> [MetaPreview] {
        let lang = language.isEmpty ? "en" : language
        let short = String(lang.prefix(2))
        let media = tv ? "tv" : "movie"
        guard let url = URL(string: "https://api.themoviedb.org/3/trending/\(media)/day?api_key=\(apiKey)&language=\(lang)"),
              let response = try? await URLSession.shared.data(from: url),
              let trending = try? JSONDecoder().decode(TrendingResponse.self, from: response.0) else {
            NSLog("[TrendingHero] trending %@ request failed", media)
            return []
        }
        let ids = (trending.results ?? []).prefix(limit).map(\.id)
        let details = await withTaskGroup(of: (Int, Details?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    let address = "https://api.themoviedb.org/3/\(media)/\(id)?api_key=\(apiKey)&language=\(lang)"
                        + "&append_to_response=images,external_ids&include_image_language=\(short),en,null"
                    guard let url = URL(string: address),
                          let response = try? await URLSession.shared.data(from: url) else { return (index, nil) }
                    return (index, try? JSONDecoder().decode(Details.self, from: response.0))
                }
            }
            var out: [Int: Details] = [:]
            for await (index, detail) in group { if let detail { out[index] = detail } }
            return out
        }
        return ids.indices.compactMap { index -> MetaPreview? in
            guard let d = details[index], let title = d.title ?? d.name, !title.isEmpty,
                  let backdrop = d.backdrop_path else { return nil }
            let logos = d.images?.logos ?? []
            let logo = (logos.first { $0.iso_639_1 == short } ?? logos.first { $0.iso_639_1 == "en" } ?? logos.first)?.file_path
            let imdb = (d.imdb_id ?? d.external_ids?.imdb_id).flatMap { $0.hasPrefix("tt") ? $0 : nil }
            let date = d.release_date ?? d.first_air_date
            return MetaPreview(id: imdb ?? "tmdb:\(d.id)", type: tv ? "series" : "movie", name: title,
                               poster: d.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                               banner: "https://image.tmdb.org/t/p/original\(backdrop)",
                               logo: logo.map { "https://image.tmdb.org/t/p/w500\($0)" },
                               posterShape: .poster,
                               description: d.overview, releaseInfo: date.map { String($0.prefix(4)) },
                               rawReleaseDate: date,
                               popularity: nil, voteCount: nil,
                               imdbRating: d.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                               genres: (d.genres ?? []).compactMap(\.name),
                               rawPosterUrl: nil,
                               landscapePoster: nil,
                               rawLandscapePosterUrl: nil,
                               customPosterApplied: false)
        }
    }
}

/// The hero's place in the strip, for the stage and the hero itself.
@MainActor
final class StageHeroFocus: ObservableObject {
    static let shared = StageHeroFocus()
    /// The hero is the strip's current page (its rows page past it otherwise).
    @Published private(set) var heroOnTop = false
    /// The full-screen style is in use (the stage draws the hero's backdrop sharp).
    @Published private(set) var fullBleed = false
    private init() {}
    func setOnTop(_ value: Bool) {
        if heroOnTop != value { heroOnTop = value }
    }
    func setFullBleed(_ value: Bool) {
        if fullBleed != value { fullBleed = value }
    }
}

/// The hero row (see the file header).
struct StageTrendingHeroRow: View {
    let items: [MetaPreview]
    /// The row's height (the strip's row height, so its page never grows past a row's).
    let height: CGFloat
    let fullBleed: Bool
    let onFocusItem: (MetaPreview?) -> Void
    let onSelect: (MetaPreview) -> Void

    @ObservedObject private var place = StageHeroFocus.shared
    @State private var index = 0
    @State private var lastTurn = Date()
    @FocusState private var focus: String?

    static let interval: TimeInterval = 8
    private static let cardId = "hero"

    private var current: MetaPreview? {
        guard !items.isEmpty else { return nil }
        return items[index % items.count]
    }

    var body: some View {
        let width = UIScreen.main.bounds.width - 2 * StripGeometry.edgeMargin
        let focused = focus == Self.cardId
        Button {
            if let current { onSelect(current) }
        } label: {
            Group {
                if fullBleed {
                    fullBleedLabel(width: width, focused: focused)
                } else {
                    cardLabel(width: width, focused: focused)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: current?.id)
            .animation(.easeOut(duration: 0.18), value: focused)
        }
        .buttonStyle(StageHeroButtonStyle())
        .focused($focus, equals: Self.cardId)
        .onMoveCommand { direction in
            switch direction {
            case .left: step(-1)
            case .right: step(1)
            default: break
            }
        }
        .pinnedRowUpFallbackTarget(rowKey: StageTrendingHeroSetting.rowKey, firstId: Self.cardId, focus: $focus)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        // Device pass (Steven: the hero's bottom showed above the rows after a Down): gone once
        // the strip pages past it.
        .opacity(place.heroOnTop ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: place.heroOnTop)
        // The page fits the hero (no info band under it).
        .preference(key: StripRowSkipsInfoBandKey.self, value: true)
        .onChange(of: focus) { _, id in
            onFocusItem(id == Self.cardId ? current : nil)
        }
        .onAppear { if place.heroOnTop, let current { onFocusItem(current) } }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Date().timeIntervalSince(lastTurn) >= Self.interval { step(1) }
            }
        }
    }

    private func step(_ delta: Int) {
        let count = items.count
        guard count > 1 else { return }
        index = (index + delta + count) % count
        lastTurn = Date()
        // The stage follows the hero while it is on top (focused or with focus on the bar above).
        if focus == Self.cardId || place.heroOnTop { onFocusItem(current) }
    }

    // MARK: Card style

    private func cardLabel(width: CGFloat, focused: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 31 / 255, green: 38 / 255, blue: 48 / 255)
            if let current {
                CachedAsyncImage(string: current.banner ?? "", contentMode: .fill,
                                 decodeSize: .points(width: width, height: height))
                    .frame(width: width, height: height)
                    .clipped()
                    .id(current.id)
                    .transition(.opacity)
            }
            LinearGradient(stops: [
                .init(color: .black.opacity(0.85), location: 0),
                .init(color: .black.opacity(0.35), location: 0.45),
                .init(color: .clear, location: 0.7),
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            if let current {
                info(current)
                    .id("info-\(current.id)")
                    .transition(.opacity)
                    .padding(.leading, 56)
                    .padding(.bottom, 44)
            }
            dots
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 40)
                .padding(.bottom, 36)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white, lineWidth: focused ? 5 : 0)
        }
        .shadow(color: .black.opacity(focused ? 0.5 : 0.25), radius: focused ? 24 : 10, y: 10)
    }

    // MARK: Full-screen style

    /// The backdrop is the stage's (`StageBlurredArt`); the row is the text and a pill.
    private func fullBleedLabel(width: CGFloat, focused: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if let current {
                VStack(alignment: .leading, spacing: 22) {
                    info(current)
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                        Text("Voir la fiche")
                    }
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(focused ? Color.black : Color.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background {
                        Capsule(style: .continuous)
                            .fill(focused ? Color.white : Color.white.opacity(0.18))
                    }
                    .scaleEffect(focused ? 1.06 : 1, anchor: .leading)
                }
                .id("info-\(current.id)")
                .transition(.opacity)
                .padding(.bottom, 20)
            }
            dots
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 20)
                .padding(.bottom, 30)
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func info(_ item: MetaPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let logo = item.logo, !logo.isEmpty {
                CachedAsyncImage(string: logo, contentMode: .fit, decodeSize: .points(width: 560, height: 170))
                    .frame(maxWidth: 560, maxHeight: 170, alignment: .bottomLeading)
            } else {
                Text(item.name)
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
            }
            Text(meta(item))
                .font(Theme.Font.metaStrong)
                .foregroundStyle(Color.white)
                .lineLimit(1)
            if let synopsis = item.description_, !synopsis.isEmpty {
                Text(synopsis)
                    .font(Theme.Font.synopsis)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(3)
                    .frame(width: 760, alignment: .leading)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
    }

    private func meta(_ item: MetaPreview) -> String {
        var parts: [String] = []
        if let year = item.releaseInfo, !year.isEmpty { parts.append(year) }
        parts.append(contentsOf: item.genres.prefix(2))
        if let rating = item.imdbRating, !rating.isEmpty { parts.append("★ \(rating)") }
        return parts.joined(separator: " · ")
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<items.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == index ? 1 : 0.35))
                    .frame(width: i == index ? 26 : 9, height: 9)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: index)
    }
}

private struct StageHeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
