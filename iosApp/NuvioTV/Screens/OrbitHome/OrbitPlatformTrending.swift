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

    private var cache: [Int: (movies: [MetaPreview], series: [MetaPreview])] = [:]
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
            withAnimation(.easeInOut(duration: 0.25)) { title = nil; movies = []; series = [] }
            return
        }
        guard provider != current else { return }
        current = provider
        pending?.cancel()
        if let cached = cache[provider] {
            withAnimation(.easeInOut(duration: 0.25)) { title = folderTitle; movies = cached.movies; series = cached.series }
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
            withAnimation(.easeInOut(duration: 0.25)) {
                self.title = found.movies.isEmpty && found.series.isEmpty ? nil : folderTitle
                self.movies = found.movies
                self.series = found.series
            }
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

    nonisolated private static func region(language: String) -> String {
        let parts = language.split(whereSeparator: { $0 == "-" || $0 == "_" })
        if parts.count > 1 { return String(parts[1]).uppercased() }
        if let region = Locale.current.region?.identifier, region.count == 2 { return region }
        return "FR"
    }

    nonisolated private static func fetch(provider: Int, apiKey: String,
                                          language: String) async -> (movies: [MetaPreview], series: [MetaPreview]) {
        let lang = language.isEmpty ? "fr-FR" : language
        let region = region(language: lang)
        async let movies = page(media: "movie", provider: provider, region: region, apiKey: apiKey, language: lang)
        async let series = page(media: "tv", provider: provider, region: region, apiKey: apiKey, language: lang)
        return await (movies, series)
    }

    nonisolated private static func page(media: String, provider: Int, region: String, apiKey: String,
                                         language: String) async -> [MetaPreview] {
        guard let url = URL(string: "https://api.themoviedb.org/3/discover/\(media)?api_key=\(apiKey)&language=\(language)"
                            + "&watch_region=\(region)&with_watch_providers=\(provider)"
                            + "&with_watch_monetization_types=flatrate&sort_by=popularity.desc&page=1"),
              let response = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: response.0) else { return [] }
        let tv = media == "tv"
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

/// The rows under the platforms: "Films populaires sur Netflix", "Séries populaires sur Netflix",
/// each scrolling sideways, each poster opening its title.
struct OrbitPlatformTrendingRow: View {
    @ObservedObject var model = OrbitPlatformTrendingModel.shared
    @FocusState private var focused: String?
    /// When the focus last left the rows (the platforms keep their own landing when coming back up).
    @MainActor static var lostAt: TimeInterval = 0

    static let posterWidth: CGFloat = 170
    static let posterHeight: CGFloat = 255
    static let spacing: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let title = model.title {
                if !model.movies.isEmpty {
                    row(heading: String(format: String(localized: "Films populaires sur %@"), title),
                        items: model.movies, key: "movies-\(title)")
                }
                if !model.series.isEmpty {
                    row(heading: String(format: String(localized: "Séries populaires sur %@"), title),
                        items: model.series, key: "series-\(title)")
                }
            }
        }
        .onChange(of: focused) { _, id in
            if id == nil { Self.lostAt = ProcessInfo.processInfo.systemUptime }
        }
    }

    private func row(heading: String, items: [MetaPreview], key: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.spacing) {
                    ForEach(items, id: \.id) { item in
                        NavigationLink(value: TitleRoute(preview: item)) {
                            OrbitTrendingPoster(item: item, focused: focused == "\(key)/\(item.id)")
                        }
                        .buttonStyle(OrbitPlatformTileStyle())
                        .focused($focused, equals: "\(key)/\(item.id)")
                    }
                }
                .padding(.vertical, 14)
                .padding(.trailing, OrbitHomeLayout.margin)
            }
            .scrollClipDisabled()
            .padding(.vertical, -14)
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0), lineWidth: 4)
        }
        .scaleEffect(focused ? 1.08 : 1)
        .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 16, y: 8)
        .animation(.easeOut(duration: 0.14), value: focused)
        .accessibilityLabel(item.name)
    }
}
