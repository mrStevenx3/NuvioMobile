import Combine
import SharedCore
import SwiftUI

// Steven's fork (Orbit Home): a hero at the very top of Home's Films page, cycling through TMDB's
// most watched films of the week (`trending/movie/week`). It is the strip's first row: one wide
// focusable card (Select opens the film, Left / Right go to the previous / next one, it moves on by
// itself every few seconds), and its film is reported to the stage like any focused card, so the
// blurred backdrop follows it. While it holds focus the stage's own corner logo and the info band
// under the rows hide (`StageHeroFocus`): the card carries its own.

/// Home Screen ▸ "Trending Hero" (Stage layout), on by default.
nonisolated enum StageTrendingHeroSetting {
    static let defaultsKey = "stage_trending_hero"
    static let defaultValue = true
    static let rowKey = "trending-hero"
}

/// The hero's films, loaded once per session (again after six hours).
@MainActor
final class StageTrendingHeroModel: ObservableObject {
    static let shared = StageTrendingHeroModel()

    @Published private(set) var items: [MetaPreview] = []
    private var loadedAt: Date?
    private var loading = false

    private init() {}

    func loadIfNeeded() {
        if loading { return }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 6 * 3600, !items.isEmpty { return }
        loading = true
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        let language = TmdbSettingsRepository.shared.snapshot().language
        Task {
            let loaded = await Self.fetch(apiKey: key, language: language)
            self.loading = false
            guard !loaded.isEmpty else { return }
            self.items = loaded
            self.loadedAt = Date()
            NSLog("[TrendingHero] loaded %d films", loaded.count)
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
        let id: Int
        let imdb_id: String?
        let title: String?
        let overview: String?
        let poster_path: String?
        let backdrop_path: String?
        let release_date: String?
        let vote_average: Double?
        let genres: [Genre]?
        let images: Images?
    }

    nonisolated static let limit = 10

    nonisolated private static func fetch(apiKey: String, language: String) async -> [MetaPreview] {
        let lang = language.isEmpty ? "en" : language
        let short = String(lang.prefix(2))
        guard let url = URL(string: "https://api.themoviedb.org/3/trending/movie/week?api_key=\(apiKey)&language=\(lang)"),
              let response = try? await URLSession.shared.data(from: url),
              let trending = try? JSONDecoder().decode(TrendingResponse.self, from: response.0) else {
            NSLog("[TrendingHero] trending request failed")
            return []
        }
        let ids = (trending.results ?? []).prefix(limit).map(\.id)
        let details = await withTaskGroup(of: (Int, Details?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    let address = "https://api.themoviedb.org/3/movie/\(id)?api_key=\(apiKey)&language=\(lang)"
                        + "&append_to_response=images&include_image_language=\(short),en,null"
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
            guard let d = details[index], let title = d.title, !title.isEmpty, let backdrop = d.backdrop_path else { return nil }
            let logos = d.images?.logos ?? []
            let logo = (logos.first { $0.iso_639_1 == short } ?? logos.first { $0.iso_639_1 == "en" } ?? logos.first)?.file_path
            let imdb = d.imdb_id.flatMap { $0.hasPrefix("tt") ? $0 : nil }
            return MetaPreview(id: imdb ?? "tmdb:\(d.id)", type: "movie", name: title,
                               poster: d.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                               banner: "https://image.tmdb.org/t/p/original\(backdrop)",
                               logo: logo.map { "https://image.tmdb.org/t/p/w500\($0)" },
                               posterShape: .poster,
                               description: d.overview, releaseInfo: d.release_date.map { String($0.prefix(4)) },
                               rawReleaseDate: d.release_date,
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

/// Set while the hero holds focus: the stage hides its corner logo and info band.
@MainActor
final class StageHeroFocus: ObservableObject {
    static let shared = StageHeroFocus()
    @Published private(set) var active = false
    private init() {}
    func set(_ value: Bool) {
        if active != value { active = value }
    }
}

/// The hero row (see the file header).
struct StageTrendingHeroRow: View {
    @ObservedObject var model: StageTrendingHeroModel
    /// The card's height (the strip's row height, so its page never grows past a row's).
    let height: CGFloat
    let onFocusItem: (MetaPreview?) -> Void
    let onSelect: (MetaPreview) -> Void

    @State private var index = 0
    @State private var lastTurn = Date()
    @FocusState private var focus: String?

    static let interval: TimeInterval = 8
    private static let cardId = "hero"

    private var current: MetaPreview? {
        guard !model.items.isEmpty else { return nil }
        return model.items[index % model.items.count]
    }

    var body: some View {
        let width = UIScreen.main.bounds.width - 2 * StripGeometry.edgeMargin
        let focused = focus == Self.cardId
        Button {
            if let current { onSelect(current) }
        } label: {
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
        // The page fits the card (no info band under it).
        .preference(key: StripRowSkipsInfoBandKey.self, value: true)
        .onChange(of: focus) { _, id in
            let on = id == Self.cardId
            StageHeroFocus.shared.set(on)
            onFocusItem(on ? current : nil)
        }
        .onDisappear { StageHeroFocus.shared.set(false) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Date().timeIntervalSince(lastTurn) >= Self.interval { step(1) }
            }
        }
    }

    private func step(_ delta: Int) {
        let count = model.items.count
        guard count > 1 else { return }
        index = (index + delta + count) % count
        lastTurn = Date()
        if focus == Self.cardId { onFocusItem(current) }
    }

    @ViewBuilder
    private func info(_ item: MetaPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("N° \((index % max(model.items.count, 1)) + 1) des films de la semaine")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
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
            ForEach(0..<model.items.count, id: \.self) { i in
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
