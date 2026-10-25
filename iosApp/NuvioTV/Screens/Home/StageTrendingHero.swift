import Combine
import SharedCore
import SwiftUI

// Steven's fork (Orbit Home): a hero at the very top of Home's Films and Séries pages, cycling
// through TMDB's "incontournables" (most voted, rated 7.5+; see `fetch`). Was the trending titles (Steven
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
        // Pass 3 (Steven: the trending titles are the same as his Nouveaux films / Top 10 rows):
        // "Les incontournables" — the most voted titles rated 7.5+, a different page of 20 every
        // day of the week, shuffled, so the hero is a catalogue of its own.
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let page = day % 7 + 1
        let address = "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(lang)"
            + "&sort_by=vote_count.desc&vote_average.gte=7.5&page=\(page)"
        guard let url = URL(string: address),
              let response = try? await URLSession.shared.data(from: url),
              let trending = try? JSONDecoder().decode(TrendingResponse.self, from: response.0) else {
            NSLog("[TrendingHero] trending %@ request failed", media)
            return []
        }
        var generator = SeededGenerator(seed: UInt64(day) &* (tv ? 7919 : 104_729))
        let ids = Array((trending.results ?? []).map(\.id).shuffled(using: &generator).prefix(limit))
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
                               logo: logo.map { "https://image.tmdb.org/t/p/w500\(OrbitMetaStore.decodable($0))" },
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

/// The day's shuffle, the same all day (the hero does not reshuffle on every launch).
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
