import Combine
import SharedCore
import SwiftUI

// Orbit Home (Steven's fork): the line under the focused title reads
// "👍 74%  2024  Action  2h 29m" and a three-line synopsis, with the title's logo in its frame.
// Catalog previews rarely carry the runtime, the TMDB score or a logo, so the focused title (and
// the next few) are looked up on TMDB once: `find` from an IMDb id (or the TMDB id itself), then the
// details with images, in the user's TMDB language. Results stay in memory for the session.

/// What Orbit Home shows about one title, beyond its catalog preview.
nonisolated struct OrbitMeta: Equatable, Sendable {
    var percent: Int?
    var year: String?
    var genre: String?
    var runtime: String?
    var overview: String?
    var logo: String?
    var backdrop: String?
    /// Steven: the English synopsis, only when there is none in his language (a title too new to
    /// be translated) — better than an empty space under the title.
    var overviewEnglish: String? = nil
}

@MainActor
final class OrbitMetaStore: ObservableObject {
    static let shared = OrbitMetaStore()

    @Published private(set) var metas: [String: OrbitMeta] = [:]
    private var inFlight = Set<String>()
    private var failed = Set<String>()

    private init() {}

    func meta(for item: MetaPreview) -> OrbitMeta? { metas[Self.key(item)] }

    nonisolated static func key(_ item: MetaPreview) -> String { "\(item.type):\(item.id)" }

    /// Looks up the titles not known yet (the focused one first).
    func request(_ items: [MetaPreview]) {
        for item in items {
            let key = Self.key(item)
            guard metas[key] == nil, !inFlight.contains(key), !failed.contains(key) else { continue }
            guard let ref = Self.reference(for: item) else { failed.insert(key); continue }
            inFlight.insert(key)
            let apiKey = TmdbSettingsRepository.shared.effectiveApiKey()
            let language = TmdbSettingsRepository.shared.snapshot().language
            Task {
                let found = await Self.load(ref: ref, apiKey: apiKey, language: language)
                self.inFlight.remove(key)
                if let found { self.metas[key] = found } else { self.failed.insert(key) }
            }
        }
    }

    // MARK: TMDB

    nonisolated enum Reference: Sendable {
        case tmdb(id: Int, tv: Bool)
        case imdb(id: String, tv: Bool)
    }

    nonisolated static func reference(for item: MetaPreview) -> Reference? {
        let tv = item.type != "movie"
        let raw = item.id
        if raw.hasPrefix("tmdb:"), let id = Int(raw.dropFirst(5).prefix { $0.isNumber }) {
            return .tmdb(id: id, tv: tv)
        }
        let imdb = raw.split(separator: ":").first.map(String.init) ?? raw
        if imdb.hasPrefix("tt") { return .imdb(id: imdb, tv: tv) }
        return nil
    }

    nonisolated private struct FindResponse: Decodable {
        nonisolated struct Hit: Decodable { let id: Int }
        let movie_results: [Hit]?
        let tv_results: [Hit]?
    }

    nonisolated private struct Details: Decodable {
        nonisolated struct Genre: Decodable { let name: String? }
        nonisolated struct Logo: Decodable {
            let file_path: String?
            let iso_639_1: String?
        }
        nonisolated struct Images: Decodable { let logos: [Logo]? }
        let overview: String?
        let release_date: String?
        let first_air_date: String?
        let vote_average: Double?
        let runtime: Int?
        let episode_run_time: [Int]?
        let genres: [Genre]?
        let images: Images?
        let backdrop_path: String?
    }

    nonisolated private static func load(ref: Reference, apiKey: String, language: String) async -> OrbitMeta? {
        let lang = language.isEmpty ? "en" : language
        let short = String(lang.prefix(2))
        let tmdbId: Int
        let tv: Bool
        switch ref {
        case .tmdb(let id, let isTv):
            tmdbId = id
            tv = isTv
        case .imdb(let imdb, let isTv):
            guard let url = URL(string: "https://api.themoviedb.org/3/find/\(imdb)?api_key=\(apiKey)&external_source=imdb_id"),
                  let response = try? await URLSession.shared.data(from: url),
                  let found = try? JSONDecoder().decode(FindResponse.self, from: response.0) else { return nil }
            let hits = isTv ? (found.tv_results ?? []) + (found.movie_results ?? [])
                            : (found.movie_results ?? []) + (found.tv_results ?? [])
            guard let first = hits.first else { return nil }
            tmdbId = first.id
            tv = isTv ? !(found.tv_results ?? []).isEmpty : (found.movie_results ?? []).isEmpty
        }
        let media = tv ? "tv" : "movie"
        guard let url = URL(string: "https://api.themoviedb.org/3/\(media)/\(tmdbId)?api_key=\(apiKey)&language=\(lang)"
                            + "&append_to_response=images&include_image_language=\(short),en,null"),
              let response = try? await URLSession.shared.data(from: url),
              let d = try? JSONDecoder().decode(Details.self, from: response.0) else { return nil }
        let minutes = d.runtime ?? d.episode_run_time?.first
        let runtime = minutes.flatMap { m -> String? in
            guard m > 0 else { return nil }
            // French, as on the film's page: "2 h 20", "2 h", "43 min".
            return m >= 60 ? (m % 60 == 0 ? "\(m / 60) h" : String(format: "%d h %02d", m / 60, m % 60)) : "\(m) min"
        }
        let overview = d.overview.flatMap { $0.isEmpty ? nil : $0 }
        var english: String?
        if overview == nil, short != "en",
           let enURL = URL(string: "https://api.themoviedb.org/3/\(media)/\(tmdbId)?api_key=\(apiKey)&language=en-US"),
           let enResponse = try? await URLSession.shared.data(from: enURL),
           let en = try? JSONDecoder().decode(Details.self, from: enResponse.0) {
            english = en.overview.flatMap { $0.isEmpty ? nil : $0 }
        }
        let logos = d.images?.logos ?? []
        let logo = (logos.first { $0.iso_639_1 == short } ?? logos.first { $0.iso_639_1 == "en" } ?? logos.first)?.file_path
        return OrbitMeta(percent: d.vote_average.flatMap { $0 > 0 ? Int(($0 * 10).rounded()) : nil },
                         year: (d.release_date ?? d.first_air_date).map { String($0.prefix(4)) }.flatMap { $0.isEmpty ? nil : $0 },
                         genre: d.genres?.first?.name,
                         runtime: runtime,
                         overview: overview,
                         logo: logo.map { "https://image.tmdb.org/t/p/w500\($0)" },
                         backdrop: d.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                         overviewEnglish: english)
    }
}

/// The meta line and synopsis for one title, from its TMDB meta when known, else its preview.
nonisolated struct OrbitInfo: Equatable {
    var percent: Int?
    var parts: [String]
    var synopsis: String
    var logo: String?

    static func make(_ item: MetaPreview, meta: OrbitMeta?) -> OrbitInfo {
        let rating: Int? = meta?.percent ?? item.imdbRating.flatMap { Double($0) }.map { Int(($0 * 10).rounded()) }
        var parts: [String] = []
        if let year = meta?.year ?? item.releaseInfo.flatMap({ $0.isEmpty ? nil : String($0.prefix(4)) }) {
            parts.append(year)
        }
        if let genre = meta?.genre ?? item.genres.first { parts.append(genre) }
        if let runtime = meta?.runtime { parts.append(runtime) }
        let own: String? = item.description_
        let logo: String? = item.logo
        return OrbitInfo(percent: rating, parts: parts,
                         synopsis: meta?.overview ?? (own?.isEmpty == false ? own : nil) ?? meta?.overviewEnglish ?? "",
                         logo: meta?.logo ?? ((logo?.isEmpty ?? true) ? nil : logo))
    }
}

/// "👍 74%  2024  Action  2h 29m".
struct OrbitMetaLine: View {
    let info: OrbitInfo
    var size: CGFloat = OrbitHomeLayout.metaFont

    var body: some View {
        HStack(spacing: 18) {
            if let percent = info.percent {
                HStack(spacing: 8) {
                    Image(systemName: "hand.thumbsup.fill")
                    Text("\(percent)%")
                }
                .foregroundStyle(OrbitHomeLayout.green)
            }
            ForEach(Array(info.parts.enumerated()), id: \.offset) { _, part in
                Text(part).foregroundStyle(Color.white)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .lineLimit(1)
    }
}
