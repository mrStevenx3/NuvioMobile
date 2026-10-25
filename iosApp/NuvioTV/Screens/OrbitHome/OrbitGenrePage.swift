import Combine
import SharedCore
import SwiftUI

// Orbit Home (Steven's fork): a genre chip opens this page — the genre's most popular titles on
// TMDB, as a poster grid that loads more as it is scrolled.

struct OrbitGenreRoute: Hashable {
    let genre: OrbitGenre
}

@MainActor
final class OrbitGenrePageModel: ObservableObject {
    @Published private(set) var items: [MetaPreview] = []
    @Published private(set) var loading = false
    private var page = 0
    private var done = false
    private var seen = Set<String>()
    let genre: OrbitGenre

    init(genre: OrbitGenre) { self.genre = genre }

    func loadMore() {
        guard !loading, !done else { return }
        loading = true
        let next = page + 1
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        let language = TmdbSettingsRepository.shared.snapshot().language
        let genre = genre
        Task {
            let found = await Self.fetch(genre: genre, page: next, apiKey: key, language: language)
            self.loading = false
            self.page = next
            if found.isEmpty { self.done = true }
            for item in found where self.seen.insert(item.id).inserted { self.items.append(item) }
        }
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

    nonisolated private static func fetch(genre: OrbitGenre, page: Int, apiKey: String, language: String) async -> [MetaPreview] {
        let lang = language.isEmpty ? "en" : language
        let media = genre.tv ? "tv" : "movie"
        guard let url = URL(string: "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(lang)"
                            + "&with_genres=\(genre.id)&sort_by=popularity.desc&vote_count.gte=150&page=\(page)"),
              let response = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: response.0) else { return [] }
        return (decoded.results ?? []).compactMap { r -> MetaPreview? in
            guard let name = r.title ?? r.name, !name.isEmpty, let poster = r.poster_path else { return nil }
            let date = r.release_date ?? r.first_air_date
            return MetaPreview(id: "tmdb:\(r.id)", type: genre.tv ? "series" : "movie", name: name,
                               poster: "https://image.tmdb.org/t/p/w780\(poster)",
                               banner: r.backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                               logo: nil, posterShape: .poster,
                               description: r.overview, releaseInfo: date.map { String($0.prefix(4)) },
                               rawReleaseDate: date, popularity: nil, voteCount: nil,
                               imdbRating: r.vote_average.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
                               genres: [genre.name], rawPosterUrl: nil, landscapePoster: nil,
                               rawLandscapePosterUrl: nil, customPosterApplied: false)
        }
    }
}

struct OrbitGenrePage: View {
    @StateObject private var model: OrbitGenrePageModel

    init(genre: OrbitGenre) {
        _model = StateObject(wrappedValue: OrbitGenrePageModel(genre: genre))
    }

    private static let columns = 6
    private static let spacing: CGFloat = 36

    var body: some View {
        let width = floor((OrbitHomeLayout.screenWidth - 2 * OrbitHomeLayout.margin
                           - CGFloat(Self.columns - 1) * Self.spacing) / CGFloat(Self.columns))
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                Text(model.genre.name)
                    .font(.system(size: 54, weight: .heavy))
                    .foregroundStyle(Color.white)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: Self.spacing, alignment: .top),
                                         count: Self.columns),
                          alignment: .leading, spacing: Self.spacing) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: TitleRoute(preview: item)) {
                            PosterCard(title: item.name, imageURL: item.poster, fallbackImageURL: item.banner,
                                       width: width, height: floor(width * 1.5), showTitle: false)
                        }
                        .cardFocusButtonStyle()
                        .posterButtonShape()
                        .onAppear {
                            if index >= model.items.count - 12 { model.loadMore() }
                        }
                    }
                }
                if model.loading { ProgressView() }
            }
            .padding(.horizontal, OrbitHomeLayout.margin)
            .padding(.top, 60)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .background(OrbitHomeLayout.background.ignoresSafeArea())
        .onAppear { if model.items.isEmpty { model.loadMore() } }
    }
}
