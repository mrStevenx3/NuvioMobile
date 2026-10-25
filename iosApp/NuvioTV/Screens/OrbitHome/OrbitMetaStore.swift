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
    /// The poster without its title (Disney+'s Top 10 cards draw the logo themselves), else TMDB's.
    var cleanPoster: String? = nil
    /// The French age rating ("TP", "12", "16"…), nil when TMDB has none.
    var certification: String? = nil
    /// TMDB's poster in the user's language (with its title), for Netflix's portrait tiles.
    var titledPoster: String? = nil
    /// A poster in the user's language exactly (nil when TMDB has none: the catalog's stays).
    var localPoster: String? = nil
    /// The production companies and networks (Netflix's "N" on its own titles).
    var producers: [String] = []
    /// Series: the number of seasons.
    var seasons: Int? = nil
    /// Steven (Orbit Home, 2026-10-25): TMDB's subscription platforms for the title in France
    /// (watch-provider ids), for its platform badge. Empty for a title on none.
    var platforms: [Int] = []
}

@MainActor
final class OrbitMetaStore: ObservableObject {
    static let shared = OrbitMetaStore()

    @Published private(set) var metas: [String: OrbitMeta] = [:]
    private var inFlight = Set<String>()
    /// TMDB has no such title (or no id to look it up by): never asked again this session.
    private var failed = Set<String>()
    /// Steven (2026-10-25, logos gone on titles that have one): a lookup that failed on the network
    /// or TMDB's rate limit is retried later instead of being given up for the whole session.
    private var retries: [String: (count: Int, after: Date)] = [:]
    /// Waiting for a free slot, the focused title first.
    private var queue: [(key: String, ref: Reference)] = []
    /// A burst of tiles (Discover's grid) stays under TMDB's rate limit.
    private static let maxConcurrent = 6
    private static let retryDelays: [TimeInterval] = [2, 8, 30]

    /// Fluidity (Steven, 2026-10-25, before the IPA): every title found used to publish on its own,
    /// re-rendering every row on screen once per title while the remote was moving. The results
    /// arriving within a short beat are published together.
    private var pending: [String: OrbitMeta] = [:]
    private var flushScheduled = false

    private init() {}

    private func publish(_ meta: OrbitMeta, for key: String) {
        pending[key] = meta
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            guard !self.pending.isEmpty else { return }
            self.metas.merge(self.pending) { _, new in new }
            self.pending.removeAll()
        }
    }

    func meta(for item: MetaPreview) -> OrbitMeta? { metas[Self.key(item)] }

    nonisolated static func key(_ item: MetaPreview) -> String { "\(item.type):\(item.id)" }

    /// Looks up the titles not known yet (the focused one first).
    func request(_ items: [MetaPreview]) {
        var front: [(key: String, ref: Reference)] = []
        for item in items {
            let key = Self.key(item)
            guard metas[key] == nil, pending[key] == nil, !inFlight.contains(key), !failed.contains(key) else { continue }
            if let retry = retries[key], retry.after > Date() { continue }
            guard let ref = Self.reference(for: item) else { failed.insert(key); continue }
            queue.removeAll { $0.key == key }
            front.append((key, ref))
        }
        queue.insert(contentsOf: front, at: 0)
        pump()
    }

    private func pump() {
        while inFlight.count < Self.maxConcurrent, !queue.isEmpty {
            let (key, ref) = queue.removeFirst()
            guard metas[key] == nil, pending[key] == nil, !inFlight.contains(key), !failed.contains(key) else { continue }
            inFlight.insert(key)
            let apiKey = TmdbSettingsRepository.shared.effectiveApiKey()
            let language = TmdbSettingsRepository.shared.snapshot().language
            Task {
                let outcome = await Self.load(ref: ref, apiKey: apiKey, language: language)
                self.inFlight.remove(key)
                switch outcome {
                case .found(let meta):
                    self.retries[key] = nil
                    self.publish(meta, for: key)
                case .missing:
                    self.failed.insert(key)
                case .transient:
                    let count = (self.retries[key]?.count ?? 0) + 1
                    if count > Self.retryDelays.count {
                        self.failed.insert(key)
                    } else {
                        let delay = Self.retryDelays[count - 1]
                        self.retries[key] = (count, Date().addingTimeInterval(delay))
                        // Retried on its own: the tile may already be on screen and ask no more.
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.1) {
                            guard self.metas[key] == nil, !self.failed.contains(key) else { return }
                            self.queue.append((key, ref))
                            self.pump()
                        }
                    }
                }
                self.pump()
            }
        }
    }

    // MARK: TMDB

    nonisolated enum Reference: Sendable {
        case tmdb(id: Int, tv: Bool)
        /// `name` / `year`: TMDB's search, when the IMDb id is not linked on TMDB yet (new titles).
        case imdb(id: String, tv: Bool, name: String, year: String?)
    }

    nonisolated static func reference(for item: MetaPreview) -> Reference? {
        let tv = item.type != "movie"
        let raw = item.id
        if raw.hasPrefix("tmdb:"), let id = Int(raw.dropFirst(5).prefix { $0.isNumber }) {
            return .tmdb(id: id, tv: tv)
        }
        let imdb = raw.split(separator: ":").first.map(String.init) ?? raw
        let year: String? = item.releaseInfo.map { String($0.prefix(4)) }.flatMap { Int($0) != nil ? $0 : nil }
        if imdb.hasPrefix("tt") { return .imdb(id: imdb, tv: tv, name: item.name, year: year) }
        return nil
    }

    nonisolated private struct SearchResponse: Decodable {
        nonisolated struct Hit: Decodable { let id: Int }
        let results: [Hit]?
    }

    nonisolated private struct ImagesResponse: Decodable {
        nonisolated struct Logo: Decodable {
            let file_path: String?
            let iso_639_1: String?
        }
        let logos: [Logo]?
    }

    nonisolated private struct FindResponse: Decodable {
        nonisolated struct Hit: Decodable { let id: Int }
        let movie_results: [Hit]?
        let tv_results: [Hit]?
    }

    /// TMDB's "watch/providers" (appended to the details): the subscription platforms per country.
    nonisolated private struct ProvidersOnly: Decodable {
        nonisolated struct Region: Decodable {
            nonisolated struct Provider: Decodable { let provider_id: Int }
            let flatrate: [Provider]?
        }
        nonisolated struct Results: Decodable { let results: [String: Region]? }
        let providers: Results?
        enum CodingKeys: String, CodingKey { case providers = "watch/providers" }
    }

    nonisolated private struct Details: Decodable {
        nonisolated struct Genre: Decodable { let name: String? }
        nonisolated struct Logo: Decodable {
            let file_path: String?
            let iso_639_1: String?
        }
        nonisolated struct Images: Decodable {
            let logos: [Logo]?
            let posters: [Logo]?
        }
        nonisolated struct ReleaseDates: Decodable {
            nonisolated struct Country: Decodable {
                nonisolated struct Entry: Decodable { let certification: String? }
                let iso_3166_1: String?
                let release_dates: [Entry]?
            }
            let results: [Country]?
        }
        nonisolated struct ContentRatings: Decodable {
            nonisolated struct Rating: Decodable {
                let iso_3166_1: String?
                let rating: String?
            }
            let results: [Rating]?
        }
        nonisolated struct Named: Decodable { let name: String? }
        let poster_path: String?
        let production_companies: [Named]?
        let networks: [Named]?
        let number_of_seasons: Int?
        let release_dates: ReleaseDates?
        let content_ratings: ContentRatings?
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

    nonisolated enum Outcome: Sendable {
        case found(OrbitMeta)
        /// TMDB answered: no such title.
        case missing
        /// The network, a timeout or the rate limit: worth another try.
        case transient
    }

    /// The body of a TMDB answer; nil on a network error or a status other than 200 (404: missing).
    nonisolated private static func fetch(_ url: URL) async -> (data: Data?, missing: Bool) {
        guard let result = try? await URLSession.shared.data(from: url) else { return (nil, false) }
        let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 { return (result.0, false) }
        return (nil, status == 404)
    }

    /// Ids only, never the key.
    nonisolated private static func log(_ line: String) {
        NSLog("%@", "[OrbitMeta] \(line)")
    }

    /// Steven (La Femme de ménage, Crystal Lake: their logo stayed text): many new TMDB logos are
    /// SVG, which the Apple TV cannot decode; TMDB serves a PNG of them at any sized rendition.
    nonisolated static func decodable(_ path: String) -> String {
        path.lowercased().hasSuffix(".svg") ? String(path.dropLast(4)) + ".png" : path
    }

    nonisolated private static func load(ref: Reference, apiKey: String, language: String) async -> Outcome {
        let lang = language.isEmpty ? "en" : language
        let short = String(lang.prefix(2))
        let tmdbId: Int
        let tv: Bool
        switch ref {
        case .tmdb(let id, let isTv):
            tmdbId = id
            tv = isTv
        case .imdb(let imdb, let isTv, let name, let year):
            guard let url = URL(string: "https://api.themoviedb.org/3/find/\(imdb)?api_key=\(apiKey)&external_source=imdb_id") else { return .missing }
            let response = await fetch(url)
            guard let body = response.data else { return response.missing ? .missing : .transient }
            guard let found = try? JSONDecoder().decode(FindResponse.self, from: body) else { return .transient }
            let hits = isTv ? (found.tv_results ?? []) + (found.movie_results ?? [])
                            : (found.movie_results ?? []) + (found.tv_results ?? [])
            if let first = hits.first {
                tmdbId = first.id
                tv = isTv ? !(found.tv_results ?? []).isEmpty : (found.movie_results ?? []).isEmpty
            } else {
                // Steven (2026-10-25, Crystal Lake / La Femme de ménage): a new title's IMDb id is
                // often not linked on TMDB yet; its name (and year) finds it.
                let media = isTv ? "tv" : "movie"
                let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let yearKey = isTv ? "first_air_date_year" : "year"
                guard !query.isEmpty,
                      let searchURL = URL(string: "https://api.themoviedb.org/3/search/\(media)?api_key=\(apiKey)&language=\(lang)&query=\(query)"
                                          + (year.map { "&\(yearKey)=\($0)" } ?? "")) else { return .missing }
                let searched = await fetch(searchURL)
                guard let searchBody = searched.data else { return .transient }
                guard let result = try? JSONDecoder().decode(SearchResponse.self, from: searchBody) else { return .transient }
                guard let hit = result.results?.first else {
                    log("no TMDB match for \(imdb)")
                    return .missing
                }
                tmdbId = hit.id
                tv = isTv
            }
        }
        let media = tv ? "tv" : "movie"
        guard let url = URL(string: "https://api.themoviedb.org/3/\(media)/\(tmdbId)?api_key=\(apiKey)&language=\(lang)"
                            + "&append_to_response=images,watch/providers,\(tv ? "content_ratings" : "release_dates")&include_image_language=\(short),en,null") else { return .missing }
        let response = await fetch(url)
        guard let body = response.data else { return response.missing ? .missing : .transient }
        guard let d = try? JSONDecoder().decode(Details.self, from: body) else { return .transient }
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
        var logo = (logos.first { $0.iso_639_1 == short } ?? logos.first { $0.iso_639_1 == "en" } ?? logos.first)?.file_path
        if logo == nil,
           let imagesURL = URL(string: "https://api.themoviedb.org/3/\(media)/\(tmdbId)/images?api_key=\(apiKey)"),
           let body = await fetch(imagesURL).data,
           let all = try? JSONDecoder().decode(ImagesResponse.self, from: body) {
            // No logo in French or English: any language beats the title in plain text.
            logo = all.logos?.first?.file_path
        }
        if logo == nil { log("no TMDB logo for \(media)/\(tmdbId)") }
        let textless = d.images?.posters?.first { $0.iso_639_1 == nil }?.file_path
        let cleanPoster = (textless ?? d.poster_path).map { "https://image.tmdb.org/t/p/w500\($0)" }
        let region = "FR"
        let rawRating: String? = tv
            ? d.content_ratings?.results?.first { $0.iso_3166_1 == region }?.rating
            : d.release_dates?.results?.first { $0.iso_3166_1 == region }?.release_dates?
                .compactMap { $0.certification }.first { !$0.isEmpty }
        let certification = rawRating.flatMap { raw -> String? in
            let r = raw.trimmingCharacters(in: .whitespaces).uppercased()
            if r.isEmpty || r == "NR" { return nil }
            return r == "U" || r == "TOUS PUBLICS" || r == "ALL" ? "TP" : r.replacingOccurrences(of: "+", with: "")
        }
        return .found(OrbitMeta(percent: d.vote_average.flatMap { $0 > 0 ? Int(($0 * 10).rounded()) : nil },
                         year: (d.release_date ?? d.first_air_date).map { String($0.prefix(4)) }.flatMap { $0.isEmpty ? nil : $0 },
                         genre: d.genres?.first?.name,
                         runtime: runtime,
                         overview: overview,
                         logo: logo.map { "https://image.tmdb.org/t/p/w500\(Self.decodable($0))" },
                         backdrop: d.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                         overviewEnglish: english,
                         cleanPoster: cleanPoster,
                         certification: certification,
                         titledPoster: d.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                         localPoster: d.images?.posters?.first { $0.iso_639_1 == short }?.file_path
                             .map { "https://image.tmdb.org/t/p/w500\($0)" },
                         producers: ((d.production_companies ?? []) + (d.networks ?? [])).compactMap(\.name),
                         seasons: d.number_of_seasons,
                         platforms: ((try? JSONDecoder().decode(ProvidersOnly.self, from: body))?.providers?.results?[region]?
                             .flatrate ?? []).map(\.provider_id)))
    }
}

/// The meta line and synopsis for one title, from its TMDB meta when known, else its preview.
nonisolated struct OrbitInfo: Equatable {
    var percent: Int?
    var parts: [String]
    var synopsis: String
    var logo: String?
    /// The catalog's own logo, when TMDB's is the one shown (tried if TMDB's does not load).
    var logoFallback: String? = nil

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
                         logo: meta?.logo ?? ((logo?.isEmpty ?? true) ? nil : logo),
                         logoFallback: meta?.logo == nil || (logo?.isEmpty ?? true) ? nil : logo)
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
